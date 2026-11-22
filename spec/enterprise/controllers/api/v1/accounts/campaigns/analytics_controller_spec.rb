require 'rails_helper'

RSpec.describe 'Campaign analytics API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }
  let(:delivered_contact) { create(:contact, :with_phone_number, account: account) }
  let(:read_contact) { create(:contact, :with_phone_number, account: account) }
  let(:failed_contact) { create(:contact, :with_phone_number, account: account) }
  let(:skipped_contact) { create(:contact, account: account) }

  before do
    account.enable_features!(:whatsapp_campaign)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: delivered_contact,
                              status: :delivered, source_id: 'wamid.delivered')
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: read_contact,
                              status: :read, source_id: 'wamid.read')
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: failed_contact, status: :failed)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: skipped_contact, status: :skipped)
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/metrics' do
    it 'returns cumulative metrics and exact status counts' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'audience' => 4,
        'sent' => 2,
        'delivered' => 2,
        'read' => 1,
        'failed' => 1,
        'skipped' => 1,
        'status_counts' => include('delivered' => 1, 'read' => 1, 'failed' => 1, 'skipped' => 1)
      )
    end

    it 'requires the WhatsApp campaign feature' do
      account.disable_features!(:whatsapp_campaign)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires campaign access' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/contacts' do
    it 'filters and paginates recipients by exact status' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts",
          params: { status: 'read', page: 1 },
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to contain_exactly(
        include('contact' => include('id' => read_contact.id), 'status' => 'read')
      )
      expect(response.parsed_body['meta']).to include('current_page' => 1, 'total_pages' => 1, 'total_count' => 1)
    end

    # #2802: who does not read contacts sees name and phone masked, and not the message (it carries their values).
    it 'masks name, phone and message for a campaign_view role without contact_view' do
      read_contact.update!(name: 'Ana Maria Souza', phone_number: '+5511987654321')
      CampaignRecipient.find_by(contact: read_contact).update!(message_content: 'Olá Ana')
      path = "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts"
      users = [%w[campaign_view], %w[campaign_view contact_view]].map do |permissions|
        create(:user, account: account, role: :agent).tap do |user|
          user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
        end
      end

      get path, params: { status: 'read' }, headers: users.first.create_new_auth_token
      expect(response.parsed_body['payload'].sole).to include(
        'contact' => include('name' => 'Ana S.', 'phone_number' => '+55 •• •••••-4321'), 'message_content' => nil
      )
      expect(response.body).not_to include('Ana Maria Souza', '987654321', 'Olá Ana')

      get path, params: { status: 'read' }, headers: users.last.create_new_auth_token
      expect(response.parsed_body['payload'].sole).to include(
        'contact' => include('name' => 'Ana Maria Souza', 'phone_number' => '+5511987654321'), 'message_content' => 'Olá Ana'
      )
    end
  end
end
