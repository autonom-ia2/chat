require 'rails_helper'
require 'csv'

# #2802: recipients' name and e-mail are contact data. Who does not read contacts (ContactPolicy#index?; EE: contact_view)
# sees them masked in the recipients list, the report and its export; who reads contacts sees them whole.
RSpec.describe 'Email campaign recipient contact mask', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:email_campaign, account: account) }
  let!(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, name: 'Ana Lima', email: 'ana.lima@example.org') }

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

  def recipients_of(user)
    get "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/recipients", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'recipients').sole
  end

  def report_of(user)
    get "/api/v1/accounts/#{account.id}/email_campaigns/reports/#{campaign.id}/recipients", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'recipients').sole
  end

  it 'masks name and e-mail in the recipients list for a campaign_view role without contact_view' do
    expect(recipients_of(with_role(%w[campaign_view]))).to include('id' => recipient.id, 'name' => 'Ana L.', 'email' => 'a*******@example.org')
    expect(response.body).not_to include('Ana Lima', 'ana.lima@')
  end

  it 'masks name and e-mail in the report for a campaign_view role without contact_view' do
    expect(report_of(with_role(%w[campaign_view]))).to include('id' => recipient.id, 'name' => 'Ana L.', 'email' => 'a*******@example.org')
    expect(response.body).not_to include('Ana Lima', 'ana.lima@')
  end

  it 'masks the report export for a campaign_manage role without contact_view' do
    get "/api/v1/accounts/#{account.id}/email_campaigns/reports/#{campaign.id}/export",
        headers: with_role(%w[campaign_manage]).create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('a*******@example.org')
    expect(response.body).not_to include('Ana Lima', 'ana.lima@')
  end

  it 'shows name and e-mail to a role with contact_view and to the administrator' do
    [with_role(%w[campaign_view contact_view]), admin].each do |user|
      expect(recipients_of(user)).to include('name' => 'Ana Lima', 'email' => 'ana.lima@example.org')
      expect(report_of(user)).to include('name' => 'Ana Lima', 'email' => 'ana.lima@example.org')
    end
  end
end
