require 'rails_helper'

# #1005: POST /api/v1/accounts/:account_id/campaign_journey/campaigns (contract in api-1005.md).
RSpec.describe 'Campaign journey campaigns API (#1005)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular,Vencimento\nAna Souza,11987654321,10/2026\nBia Lima,21987654321,\n")
  end
  let(:bindings) do
    { '1' => { source: 'contact', value: 'first_name' }, '2' => { source: 'column', value: 'Vencimento' },
      '3' => { source: 'fixed', value: 'Equipe Hub2You' } }
  end

  def create_campaign(as: user, audience_id: audience.id, channel_name: 'whatsapp_cloud', **campaign)
    body = {
      campaign_import_id: audience_id, channel: channel_name,
      campaign: { title: 'Renovação outubro', inbox_id: channel.inbox.id, scheduled_at: nil,
                  template_params: journey_template_params, variable_bindings: bindings, variable_defaults: {} }.merge(campaign)
    }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: { 'api_access_token' => as.access_token.token },
                                                                      as: :json
  end

  it 'creates the campaign linked to the audience, and sending resolves the variables per person' do
    sent = stub_graph_messages

    create_campaign(variable_defaults: {})

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    campaign = account.campaigns.find(payload['id'])
    expect(payload).to include('display_id' => campaign.display_id, 'title' => 'Renovação outubro', 'channel' => 'whatsapp_cloud',
                               'recipients_count' => 2)
    expect(payload['scheduled_at']).to be_present
    expect(campaign).to be_one_off
    expect(campaign.audience).to eq([])
    expect(campaign.message).to eq('Olá {{1}}, sua apólice vence em {{2}}. {{3}}')
    link = CampaignAudienceLink.for_campaign(campaign)
    expect(link.campaign_import).to eq(audience)
    expect(link.variable_bindings['2']).to eq('source' => 'column', 'value' => 'Vencimento')

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.pluck('to')).to eq(['+5511987654321'])
    statuses = CampaignRecipient.where(campaign: campaign).joins(:contact).pluck('contacts.name', :status, :error_message)
    expect(statuses).to contain_exactly(['Ana Souza', 'sent', nil], ['Bia Lima', 'skipped', 'falta {{2}}'])
  end

  it 'stores the scheduled time and the variable defaults' do
    create_campaign(scheduled_at: '2026-10-06T12:00:00.000Z', variable_defaults: { '2' => 'em breve' })

    expect(response).to have_http_status(:ok)
    campaign = account.campaigns.find(response.parsed_body['id'])
    expect(campaign.scheduled_at).to eq(Time.zone.parse('2026-10-06T12:00:00Z'))
    expect(CampaignAudienceLink.for_campaign(campaign).variable_defaults).to eq('2' => 'em breve')
  end

  it 'refuses a non-Cloud WhatsApp inbox with whatsapp_cloud_required and an unknown channel with unsupported_channel' do
    other = create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false)

    create_campaign(inbox_id: other.inbox.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('whatsapp_cloud_required')

    create_campaign(channel_name: 'fax')
    expect(response.parsed_body['code']).to eq('unsupported_channel')
    expect(account.campaigns.count).to eq(0)
  end

  # J4: an audience without WhatsApp (no phone, or the channel turned off) cannot be used.
  it 'refuses an audience without WhatsApp with channel_not_in_audience' do
    email_only = saved_audience(account: account, user: user, content: "Nome,Email\nAna,ana@alfa.com.br\n", mapping: { 'name' => 0, 'email' => 1 })
    create_campaign(audience_id: email_only.id, variable_bindings: {})
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('channel_not_in_audience')

    audience.update!(channels: audience.channels.merge('whatsapp' => { 'enabled' => false, 'count' => 2 }))
    create_campaign
    expect(response.parsed_body['code']).to eq('channel_not_in_audience')
    expect(CampaignAudienceLink.count).to eq(0)
  end

  it 'refuses an audience that has not finished saving with audience_not_ready' do
    audience.update!(status: :importing)

    create_campaign

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('audience_not_ready')
  end

  it 'refuses variables bound to an unknown column or source with invalid_variable_bindings' do
    create_campaign(variable_bindings: { '2' => { source: 'column', value: 'CPF' } })
    expect(response.parsed_body['code']).to eq('invalid_variable_bindings')

    create_campaign(variable_bindings: { '1' => { source: 'contact', value: 'phone_number' } })
    expect(response.parsed_body['code']).to eq('invalid_variable_bindings')
    expect(account.campaigns.count).to eq(0)
  end

  # A4: campaign_view alone cannot schedule or send.
  it 'answers 401 to a user with campaign_view only' do
    viewer = User.create!(name: 'Leitor', email: "leitor-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    view_only = create(:custom_role, account: account, permissions: %w[campaign_view])
    AccountUser.create!(account: account, user: viewer, role: :agent, custom_role: view_only)

    create_campaign(as: viewer)

    expect(response).to have_http_status(:unauthorized)
    expect(account.campaigns.count).to eq(0)
  end

  it 'answers 404 when CAMPAIGN_JOURNEY_ENABLED is off' do
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') { create_campaign }

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['code']).to eq('campaign_journey_disabled')
  end
end
