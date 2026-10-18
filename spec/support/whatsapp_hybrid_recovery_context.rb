# chat#1489: caixa Cloud com WhatsApp API conectado, conta liberada e uma bolha "não suportada" pendente.
RSpec.shared_context 'with a pending unsupported hybrid message' do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  # Amostra real do spike F0: o id físico dentro deste wamid é 2A5D2D8DA089BE42E4D5.
  let(:wamid) { 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFDJBNUQyRDhEQTA4OUJFNDJFNEQ1AA==' }
  let(:web_id) { '2A5D2D8DA089BE42E4D5' }
  let(:placeholder) { 'This message is unavailable.' }
  let(:message) do
    create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, sender: contact,
                     content: placeholder, source_id: wamid,
                     content_attributes: { 'is_unsupported' => true, 'unsupported_error_code' => 131_060,
                                           'whatsapp_web_id' => web_id, 'hybrid_recovery' => 'pending' })
  end
  let(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  let(:engine_url) { "https://waha.test/api/hybrid-test/chats/5511937016094@c.us/messages/#{web_id}?downloadMedia=false" }
  let(:template_body) { 'Seu boleto vence amanhã.' }

  around do |example|
    with_modified_env('WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste',
                      'WHATSAPP_HYBRID_ACCOUNT_IDS' => account.id.to_s) { example.run }
  end

  before do
    account.enable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE)
    connection
  end

  def engine_message(overrides = {})
    {
      'id' => "false_5511937016094@c.us_#{web_id}", 'fromMe' => false, 'from' => '5511937016094@c.us', 'body' => '',
      'hasMedia' => false,
      '_data' => { 'Info' => { 'IsFromMe' => false },
                   'Message' => { 'templateMessage' => { 'hydratedTemplate' => {
                     'hydratedContentText' => template_body,
                     'hydratedButtons' => [{ 'HydratedButton' => { 'QuickReplyButton' => { 'displayText' => 'Já paguei' } } }]
                   } } } }
    }.merge(overrides)
  end

  def stub_engine(body = engine_message, status: 200)
    stub_request(:get, engine_url).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end
