# Públicos (#1005): a saved audience (validated with a manual column choice and imported) and a
# WhatsApp Cloud inbox whose Graph API is stubbed — specs never send a real message.
module CampaignJourneyHelpers
  JOURNEY_TEMPLATE = {
    'name' => 'renovacao', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'pt_BR', 'namespace' => 'ns_renovacao',
    'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, sua apólice vence em {{2}}. {{3}}' }]
  }.freeze

  def saved_audience(account:, user:, content:, mapping: { 'name' => 0, 'phone' => 1 })
    campaign_import = create_audience_import(account: account, user: user, content: content)
    campaign_import.update!(schema_resolution: { 'manual_mapping' => mapping, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform
    campaign_import.reload.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import.reload).perform
    campaign_import.reload
  end

  def journey_cloud_channel(account)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    channel.update!(message_templates: [JOURNEY_TEMPLATE])
    account.enable_features!(:whatsapp_campaign)
    channel
  end

  def journey_template_params(body = { '1' => '', '2' => '', '3' => 'Equipe Hub2You' })
    { 'name' => 'renovacao', 'namespace' => 'ns_renovacao', 'category' => 'MARKETING', 'language' => 'pt_BR',
      'processed_params' => { 'body' => body } }
  end

  # Captures every template message sent to the Graph API; numbers in `failing` get a Meta error;
  # on_send runs before each answer (to act in the middle of a send).
  def stub_graph_messages(failing: [], on_send: nil)
    sent = []
    matcher = ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/messages') }
    stub_request(:post, matcher).to_return do |request|
      body = JSON.parse(request.body)
      sent << body
      on_send&.call(body)
      if failing.include?(body['to'])
        { status: 400, headers: { 'Content-Type' => 'application/json' },
          body: { error: { code: 131_026, error_user_title: 'Message undeliverable', error_user_msg: 'Número sem WhatsApp' } }.to_json }
      else
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: "wamid.#{sent.size}" }] }.to_json }
      end
    end
    sent
  end
end

# SMS (#1004): Twilio SMS and Bandwidth inboxes whose HTTP APIs are stubbed — specs never send a
# real SMS. The stubs return what each send carried, in order.
module CampaignJourneySmsHelpers
  TWILIO_MESSAGES = ->(uri) { uri.host == 'api.twilio.com' && uri.path.end_with?('/Messages.json') }
  BANDWIDTH_MESSAGES = ->(uri) { uri.host == 'messaging.bandwidth.com' && uri.path.end_with?('/messages') }

  def journey_twilio_sms_inbox(account)
    create(:channel_twilio_sms, account: account).inbox
  end

  def journey_bandwidth_inbox(account)
    create(:channel_sms, account: account).inbox
  end

  # failing: { '+55…' => [code, message] } answers Twilio's error; on_send runs before each answer.
  def stub_twilio_sms(failing: {}, on_send: nil)
    sent = []
    stub_request(:post, TWILIO_MESSAGES).to_return do |request|
      body = Rack::Utils.parse_query(request.body)
      sent << body
      on_send&.call(body)
      twilio_answer(body, sent.size, failing[body['To']])
    end
    sent
  end

  def stub_bandwidth_sms(failing: [])
    sent = []
    stub_request(:post, BANDWIDTH_MESSAGES).to_return do |request|
      body = JSON.parse(request.body)
      sent << body
      if failing.include?(body['to'])
        { status: 400, headers: { 'Content-Type' => 'application/json' }, body: { description: "'to' #{body['to']} is not a mobile number" }.to_json }
      else
        { status: 202, headers: { 'Content-Type' => 'application/json' }, body: { id: "bw-#{sent.size}" }.to_json }
      end
    end
    sent
  end

  private

  def twilio_answer(body, number, failure)
    headers = { 'Content-Type' => 'application/json' }
    if failure
      { status: 400, headers: headers, body: { code: failure.first, message: failure.last, status: 400 }.to_json }
    else
      { status: 201, headers: headers, body: { sid: "SM#{number}", status: 'queued', to: body['To'], body: body['Body'] }.to_json }
    end
  end
end

RSpec.configure do |config|
  config.include CampaignJourneySmsHelpers
  config.include CampaignJourneyHelpers
end
