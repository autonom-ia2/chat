require 'rails_helper'

# #1007 — Gestão de campanhas as the multichannel overview (PRD D18, §6.10, O3).
RSpec.describe 'Campaign journey overview API (#1007)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true',
                      WHATSAPP_API_CAMPAIGNS_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:reply_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:ana) { account.contacts.create!(name: 'Ana', phone_number: '+5511987654321') }
  let(:bia) { account.contacts.create!(name: 'Bia', phone_number: '+5521987654322') }

  def whatsapp_campaign(title, scheduled_at:)
    campaign = create(:campaign, account: account, inbox: whatsapp_inbox, title: title, campaign_type: :one_off)
    # rubocop:disable Rails/SkipsModelValidations -- a completed campaign cannot be updated through the model
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:completed], scheduled_at: scheduled_at)
    # rubocop:enable Rails/SkipsModelValidations
    campaign
  end

  def recipient(campaign, contact, status)
    CampaignRecipient.create!(account: account, campaign: campaign, contact: contact, inbox: campaign.inbox, status: status)
  end

  def get_overview(params = {}, user: admin)
    get "/api/v1/accounts/#{account.id}/campaign_journey/overview", params: params, headers: { 'api_access_token' => user.access_token.token }
  end

  it 'compares the campaigns of the period across channels with replies and CRM deals' do
    recent = whatsapp_campaign('Renovação auto', scheduled_at: 2.days.ago)
    recipient(recent, ana, :read)
    recipient(recent, bia, :failed)
    old = whatsapp_campaign('Campanha antiga', scheduled_at: 60.days.ago)
    recipient(old, ana, :delivered)
    email = create(:email_campaign, account: account, name: 'Novidades de outubro', status: :sent, sent_at: 1.day.ago)
    create(:email_campaign_recipient, email_campaign: email, status: :sent, sent_at: 1.day.ago)
    conversation = create_crm_conversation(account: account, inbox: reply_inbox, contact: ana)
    CampaignJourney::CampaignMarks.mark!(conversation, recent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana — renovação', conversation_id: conversation.id, contact: ana,
                              status: :won)

    get_overview({ days: 30 })

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['campaigns'].map { |row| [row['channel'], row['name']] }).to eq(
      [['email', 'Novidades de outubro'], ['whatsapp_official', 'Renovação auto']]
    )
    whatsapp_row = payload['campaigns'].last
    expect(whatsapp_row).to include('id' => recent.display_id, 'sent' => 1, 'delivered' => 1, 'replied' => 1, 'reply_rate' => 100.0)
    expect(whatsapp_row['engagement']).to include('kind' => 'read', 'count' => 1)
    expect(payload['totals']).to include('campaigns' => 2, 'replied' => 1, 'deals' => { 'cards' => 1, 'won' => 1 })
    expect(payload['totals']['email_health']).to include('bounce_limit' => 5.0, 'complaint_limit' => 0.1)

    get_overview({ days: 90 })
    expect(response.parsed_body.dig('payload', 'totals', 'campaigns')).to eq(3)
  end

  it 'filters by channel' do
    whatsapp_campaign('Renovação auto', scheduled_at: 2.days.ago)
    create(:email_campaign, account: account, name: 'Novidades', status: :sent, sent_at: 1.day.ago)

    get_overview({ channel: 'email' })

    payload = response.parsed_body['payload']
    expect(payload['channel']).to eq('email')
    expect(payload['campaigns'].pluck('channel')).to eq(['email'])
  end

  it 'leaves drafts and scheduled campaigns out' do
    create(:email_campaign, account: account, name: 'Rascunho', status: :draft)
    create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Agendada', campaign_type: :one_off, scheduled_at: 1.day.from_now)

    get_overview

    expect(response.parsed_body.dig('payload', 'campaigns')).to eq([])
  end

  it 'needs campaign_view' do
    agent, = create_crm_agent(account: account)

    get_overview(user: agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers 404 with the journey off' do
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') { get_overview }

    expect(response).to have_http_status(:not_found)
  end
end
