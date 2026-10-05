require 'rails_helper'

RSpec.describe 'Campaigns on non-Cloud WhatsApp inboxes', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!(:whatsapp_campaign) }

  def whatsapp_channel(provider)
    create(:channel_whatsapp, account: account, provider: provider, validate_provider_config: false, sync_templates: false)
  end

  describe 'POST /api/v1/accounts/:account_id/campaigns' do
    def create_campaign_on(provider)
      post "/api/v1/accounts/#{account.id}/campaigns",
           params: { inbox_id: whatsapp_channel(provider).inbox.id, title: 'Renovação', message: 'Olá', scheduled_at: 1.day.from_now },
           headers: administrator.create_new_auth_token,
           as: :json
    end

    it 'refuses with 422 and an explainable code when the inbox is not WhatsApp Cloud' do
      create_campaign_on('default')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('whatsapp_cloud_required')
      expect(Campaign.count).to eq(0)
    end

    it 'creates the campaign on a WhatsApp Cloud inbox' do
      create_campaign_on('whatsapp_cloud')

      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/campaigns/:id' do
    let(:cloud) { whatsapp_channel('whatsapp_cloud') }
    let(:campaign) { create(:campaign, account: account, inbox: cloud.inbox, title: 'Renovação', scheduled_at: 1.day.from_now) }

    def update_campaign(params)
      patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            params: params, headers: administrator.create_new_auth_token, as: :json
    end

    it 'refuses moving the campaign to a non-Cloud inbox' do
      update_campaign(inbox_id: whatsapp_channel('default').inbox.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(campaign.reload.inbox_id).to eq(cloud.inbox.id)
    end

    it 'keeps edits that do not change the inbox working' do
      update_campaign(title: 'Renovação 2')

      expect(response).to have_http_status(:success)
      expect(campaign.reload.title).to eq('Renovação 2')
    end
  end
end
