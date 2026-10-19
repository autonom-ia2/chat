# Cenário comum dos specs do chat#1709 (fase 1): caixa híbrida pronta, conversa fora da janela de 24 h e motor falso.
RSpec.shared_context 'with a hybrid inbox for rich native' do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  # A lista nativa exige cabeçalho (sem ele o app não a exibe: sai texto, chat#1709 teste em aparelho).
  let(:options) { { type: 'options', header: 'Horários', options: [{ id: 'manha', title: 'Manhã' }, { id: 'tarde', title: 'Tarde' }] } }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0AAAA', send_text: { 'id' => 'true_5511937016094@c.us_3EB0AAAA' },
                                      start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
    Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))
  end

  def outgoing(rich_message, content: 'Qual horário fica melhor?')
    create(:message, message_type: :outgoing, content: content, conversation: conversation, account: account, inbox: inbox,
                     sender: create(:user, account: account), content_attributes: { rich_message: rich_message })
  end

  def send_by_web(message)
    WhatsappHybrid::WebTransport.new(message: message, connection: connection, origin: 'human', client: client).perform
  end

  def flag_on!
    account.enable_features!(Waha::RichNative::FLAG)
  end
end
