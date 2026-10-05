require 'rails_helper'

# #1002 — campaign marks in the filters (K6), in the contact panel (P1), the campaign label of a
# campaign message (P2) and the e-mail campaign's WhatsApp code (K4).
RSpec.describe 'Campaign journey marks API', type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:contact) { account.contacts.create!(name: 'Ana', phone_number: '+5511987654321') }
  let(:email_campaign) { create(:email_campaign, account: account, name: 'Novidades de outubro') }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:whatsapp_campaign) { create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Renovação auto — outubro', campaign_type: :one_off) }

  def marked_conversation
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    travel_to(Time.zone.parse('2026-10-01 10:00')) do
      Ctwa::CampaignBuilder.attribute!(conversation, source_id: 'link:ABC234', source_type: 'tracked_link', headline: 'Feira 2026')
    end
    travel_to(Time.zone.parse('2026-10-02 10:00')) { CampaignJourney::CampaignMarks.mark!(conversation.reload, email_campaign) }
    travel_to(Time.zone.parse('2026-10-03 10:00')) { CampaignJourney::CampaignMarks.mark!(conversation.reload, whatsapp_campaign) }
    conversation
  end

  describe 'K6 — campaign filter options' do
    it 'lists the campaigns among the filter options of Kanban and Conversations' do
      marked_conversation

      get "/api/v1/accounts/#{account.id}/ctwa_campaigns", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      options = response.parsed_body['payload'].map { |option| option.slice('source_id', 'source', 'headline') }
      expect(options).to include(
        { 'source_id' => "campaign:email:#{email_campaign.id}", 'source' => 'campaign_email', 'headline' => 'Novidades de outubro' },
        { 'source_id' => "campaign:whatsapp:#{whatsapp_campaign.id}", 'source' => 'campaign_whatsapp', 'headline' => 'Renovação auto — outubro' }
      )
    end

    it 'filters the conversations marked with a campaign' do
      conversation = marked_conversation
      create_crm_conversation(account: account, inbox: inbox, contact: account.contacts.create!(name: 'Bia', phone_number: '+5511911112222'))

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           headers: admin.create_new_auth_token,
           params: { payload: [{ attribute_key: 'campaign_source_ids', filter_operator: 'contains',
                                 values: ["\"campaign:whatsapp:#{whatsapp_campaign.id}\""], query_operator: nil }] },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([conversation.display_id])
    end
  end

  describe 'P1 — contact origins' do
    it 'returns every mark in order and the audiences of the contact' do
      conversation = marked_conversation
      audience = account.campaign_imports.create!(user: admin, name: 'Clientes auto', options: { 'flow' => 'audience' })
      audience.campaign_import_rows.create!(row_number: 1, contact_id: contact.id, status: :imported)
      old_base = account.campaign_imports.create!(user: admin, campaign_name: 'Base setembro')
      old_base.campaign_import_rows.create!(row_number: 1, contact_id: contact.id, status: :imported)
      account.campaign_imports.create!(user: admin, name: 'Outro público')
      contact_import = account.campaign_imports.create!(user: admin, name: 'Planilha de contatos', options: { 'flow' => CampaignImport::CONTACTS_FLOW })
      contact_import.campaign_import_rows.create!(row_number: 1, contact_id: contact.id, status: :imported)

      get "/api/v1/accounts/#{account.id}/campaign_journey/contact_origins/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload['marks'].map { |mark| [mark['source'], mark['headline']] }).to eq(
        [['tracked_link', 'Feira 2026'], ['campaign_email', 'Novidades de outubro'], ['campaign_whatsapp', 'Renovação auto — outubro']]
      )
      expect(payload['marks'].first['conversation_display_id']).to eq(conversation.display_id)
      expect(payload['audiences'].pluck('name')).to eq(['Clientes auto', 'Base setembro'])
    end

    it 'hides marks of conversations the agent cannot see' do
      marked_conversation
      agent, = create_crm_agent(account: account)

      get "/api/v1/accounts/#{account.id}/campaign_journey/contact_origins/#{contact.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['marks']).to eq([])
    end
  end

  describe 'P2 — campaign names of campaign messages' do
    it 'returns the names of the campaigns of the account only' do
      user = create(:user, account: account)
      api_inbox = create_whatsapp_api_inbox(account: account)
      api_campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: api_inbox, label: account.labels.create!(title: 'wa'))
      foreign = create(:campaign, title: 'De outra conta')

      get "/api/v1/accounts/#{account.id}/campaign_journey/campaign_names",
          headers: admin.create_new_auth_token,
          params: { campaign_ids: "#{whatsapp_campaign.id},#{foreign.id},x", whatsapp_api_campaign_ids: api_campaign.id.to_s }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq(
        'campaigns' => { whatsapp_campaign.id.to_s => 'Renovação auto — outubro' },
        'whatsapp_api_campaigns' => { api_campaign.id.to_s => 'Campanha WAHA' }
      )
    end
  end

  describe 'K4 — e-mail campaign WhatsApp code' do
    around do |example|
      with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { example.run }
    end

    it 'exposes the campaign code in the e-mail campaign' do
      get "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{email_campaign.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('payload', 'whatsapp_reply_code')).to eq(CampaignReplyCode.find_by!(campaign: email_campaign).code)
    end
  end
end
