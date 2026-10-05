require 'rails_helper'

# #1004: POST /api/v1/accounts/:account_id/campaign_journey/campaigns with channel "sms"
# (contract in docs/campaigns/publicos/api-1004.md), and M4 on the campaigns list API.
RSpec.describe 'Campaign journey SMS campaigns API (#1004)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { journey_twilio_sms_inbox(account) }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular,Vencimento\nAna Souza,11987654321,10/2026\nBia Lima,21987654321,\n")
  end
  let(:message) { 'Oi {{contact.first_name}}, sua parcela vence {{publico.vencimento}}.' }

  def create_sms_campaign(as: user, audience_id: audience.id, channel_name: 'sms', **campaign)
    body = {
      campaign_import_id: audience_id, channel: channel_name,
      campaign: { title: 'Parcela outubro', inbox_id: inbox.id, scheduled_at: nil, message: message,
                  variable_defaults: { 'publico.vencimento' => 'em breve' } }.merge(campaign)
    }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: { 'api_access_token' => as.access_token.token },
                                                                      as: :json
  end

  def error_code
    response.parsed_body['code']
  end

  it 'creates the SMS campaign linked to the audience, and sending renders the tokens per person' do
    sent = stub_twilio_sms

    create_sms_campaign

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    campaign = account.campaigns.find(payload['id'])
    expect(payload).to include('display_id' => campaign.display_id, 'title' => 'Parcela outubro', 'channel' => 'sms',
                               'inbox_id' => inbox.id, 'recipients_count' => 2)
    expect(payload['message_stats']).to include('encoding' => 'GSM-7', 'segments' => 1, 'per_segment' => 160)
    expect([campaign.one_off?, campaign.audience, campaign.message]).to eq([true, [], message])
    link = CampaignAudienceLink.for_campaign(campaign)
    expect([link.campaign_import, link.variable_defaults]).to eq([audience, { 'publico.vencimento' => 'em breve' }])

    Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform

    expect(sent.map { |body| [body['To'], body['Body']] }).to contain_exactly(
      ['+5511987654321', 'Oi Ana, sua parcela vence 10/2026.'], ['+5521987654321', 'Oi Bia, sua parcela vence em breve.']
    )
  end

  it 'accepts a Bandwidth SMS inbox' do
    create_sms_campaign(inbox_id: journey_bandwidth_inbox(account).id)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['channel']).to eq('sms')
  end

  it 'refuses an inbox that is not SMS (sms_inbox_required)' do
    whatsapp_twilio = create(:channel_twilio_sms, :whatsapp, account: account)
    [create(:inbox, account: account).id, whatsapp_twilio.inbox.id, 0].each do |inbox_id|
      create_sms_campaign(inbox_id: inbox_id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_code).to eq('sms_inbox_required')
    end
    expect(account.campaigns.count).to eq(0)
  end

  # J4 for SMS: the audience needs its phone channel.
  it 'refuses an audience without phones enabled (channel_not_in_audience)' do
    audience.update!(channels: audience.channels.merge('whatsapp' => audience.channels['whatsapp'].merge('enabled' => false)))

    create_sms_campaign

    expect(response).to have_http_status(:unprocessable_entity)
    expect(error_code).to eq('channel_not_in_audience')
    expect(CampaignAudienceLink.count).to eq(0)
  end

  it 'refuses unknown tokens, unknown audience columns and defaults of tokens the message does not use' do
    create_sms_campaign(message: 'Oi {{contact.email}}')
    expect([error_code, response.parsed_body.dig('details', 'unknown')]).to eq(['unsupported_variables', ['contact.email']])

    create_sms_campaign(message: 'Vence {{publico.plano}}', variable_defaults: {})
    expect([error_code, response.parsed_body.dig('details', 'unknown')]).to eq(['unknown_audience_column', ['plano']])

    create_sms_campaign(message: 'Oi {{contact.name}}')
    expect([error_code, response.parsed_body.dig('details', 'unknown')]).to eq(['invalid_variable_defaults', ['publico.vencimento']])

    create_sms_campaign(message: 'a' * 1601, variable_defaults: {})
    expect(error_code).to eq('message_too_long')
    expect(account.campaigns.count).to eq(0)
  end

  it 'refuses a schedule in the past and an empty message (invalid_campaign)' do
    create_sms_campaign(scheduled_at: 1.day.ago.iso8601)
    expect(error_code).to eq('invalid_schedule')

    create_sms_campaign(message: '', variable_defaults: {})
    expect(error_code).to eq('invalid_campaign')
  end

  it 'answers 404 for an audience of another account' do
    other_audience = saved_audience(account: create(:account), user: user, content: "Nome,Celular\nZé,11911112222\n")

    create_sms_campaign(audience_id: other_audience.id)

    expect(response).to have_http_status(:not_found)
  end

  it 'answers 404 with the journey flag off' do
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') { create_sms_campaign }

    expect(response).to have_http_status(:not_found)
    expect(error_code).to eq('campaign_journey_disabled')
  end

  # A4: campaign_view only cannot create.
  it 'answers 401 for an agent without campaign_manage' do
    agent = create(:user, account: account, role: :agent)

    create_sms_campaign(as: agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.campaigns.count).to eq(0)
  end

  # M4: the campaigns list carries the Twilio medium, so the journey list (#993, campaignRows.js)
  # keeps Twilio WhatsApp campaigns out of SMS.
  it 'lists Twilio campaigns with the inbox medium (M4)' do
    whatsapp_twilio = create(:channel_twilio_sms, :whatsapp, account: account)
    create(:campaign, account: account, inbox: inbox, title: 'SMS', message: 'Oi')
    create(:campaign, account: account, inbox: whatsapp_twilio.inbox, title: 'WhatsApp Twilio', message: 'Oi')

    get "/api/v1/accounts/#{account.id}/campaigns", headers: { 'api_access_token' => user.access_token.token }, as: :json

    expect(response).to have_http_status(:ok)
    by_title = response.parsed_body.index_by { |campaign| campaign['title'] }
    expect(by_title['SMS']['inbox']).to include('channel_type' => 'Channel::TwilioSms', 'medium' => 'sms')
    expect(by_title['WhatsApp Twilio']['inbox']).to include('channel_type' => 'Channel::TwilioSms', 'medium' => 'whatsapp')
  end
end
