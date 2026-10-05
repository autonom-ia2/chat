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

RSpec.configure do |config|
  config.include CampaignJourneyHelpers
end
