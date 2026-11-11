require 'rails_helper'

# #2802 sweep: the e-mail report endpoints that carry people (opened/clicked in the campaign detail, import issues and
# their export) mask them for who does not read contacts, and the import issues search does not read the real address.
RSpec.describe 'Email campaign report contact mask (#2802)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns/reports/#{campaign.id}" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  def with_role(permissions)
    create(:user, account: account, role: :agent).tap do |user|
      role = create(:custom_role, account: account, permissions: permissions)
      user.account_users.find_by(account: account).update!(custom_role: role)
    end
  end

  describe 'campaign detail' do
    before do
      recipient = create(:email_campaign_recipient, email_campaign: campaign, name: 'Ana Lima', email: 'ana.lima@example.org',
                                                    last_event_at: 1.hour.ago)
      recipient.email_events.create!(event_type: :open, occurred_at: 1.hour.ago)
      recipient.email_events.create!(event_type: :click, occurred_at: 1.hour.ago, url: 'https://example.org/oferta')
    end

    it 'masks who opened and clicked for a campaign_view role without contact_view' do
      get base, headers: with_role(%w[campaign_view]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['opened'].sole).to include('name' => 'Ana L.', 'email' => 'a*******@example.org')
      expect(payload['clicked'].sole).to include('name' => 'Ana L.', 'email' => 'a*******@example.org')
      expect(response.body).not_to include('Ana Lima', 'ana.lima@')
    end

    it 'shows them whole to a role with contact_view' do
      get base, headers: with_role(%w[campaign_view contact_view]).create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'opened').sole).to include('name' => 'Ana Lima', 'email' => 'ana.lima@example.org')
    end
  end

  describe 'import issues' do
    before do
      campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: 'ana.lima@exmple.org', reason_code: 'invalid_email',
                                                    suggestion: 'ana.lima@example.org')
      campaign.email_campaign_import_issues.create!(row_number: 4, raw_address: 'bruno@example.org', reason_code: 'duplicate')
    end

    it 'masks the address and the suggestion for a campaign_view role without contact_view' do
      get "#{base}/import_issues", headers: with_role(%w[campaign_view]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      issue = response.parsed_body.dig('payload', 'issues').find { |row| row['row_number'] == 3 }
      expect(issue).to include('raw_email' => 'a*******@exmple.org', 'email' => 'a*******@exmple.org',
                               'suggestion' => 'a*******@example.org')
      expect(response.body).not_to include('ana.lima@', 'bruno@')
    end

    it 'does not let a role without contact_view find out whether an address was in the file' do
      viewer = with_role(%w[campaign_view]).create_new_auth_token
      found = %w[bruno@example.org ninguem@example.org].map do |term|
        get "#{base}/import_issues", params: { q: term }, headers: viewer, as: :json
        [response.parsed_body.dig('payload', 'meta'), response.parsed_body.dig('payload', 'issues').size]
      end

      expect(found.uniq.size).to eq(1)
      expect(found.first.last).to eq(2)
    end

    it 'masks the export for a campaign_manage role without contact_view' do
      get "#{base}/import_issues/export", headers: with_role(%w[campaign_manage]).create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('a*******@exmple.org', 'b****@example.org')
      expect(response.body).not_to include('ana.lima@', 'bruno@')
    end

    it 'shows and searches the real address for a role with contact_view' do
      get "#{base}/import_issues", params: { q: 'bruno@' }, headers: with_role(%w[campaign_view contact_view]).create_new_auth_token,
                                   as: :json

      expect(response.parsed_body.dig('payload', 'issues').sole).to include('raw_email' => 'bruno@example.org')
    end
  end
end
