require 'rails_helper'

# chat#1442 — caixa oficial com WhatsApp Híbrido (chat#1067) segue pela Meta, como qualquer caixa oficial,
# mesmo quando a próxima resposta em texto livre sairia pelo WhatsApp API. O Deliverer não sabe qual será o
# próximo envio (template e pedido de contato saem pela Cloud), e pular a Meta deixaria a pausa entre os
# pedaços do agente nativo sem "digitando" e a mensagem sem ser marcada como lida.
describe Conversations::ChannelTyping::Deliverer do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

  before do
    stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}')
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'wamid.LAST',
                     created_at: 30.hours.ago)
  end

  it 'calls Meta even when the next free-form reply would go through the WhatsApp API' do
    expect(conversation.whatsapp_api_reply?).to be(true)

    described_class.new(conversation: conversation, typing_status: 'on').perform

    expect(WebMock).to have_requested(:post, meta_typing_url).once.with(body: hash_including('message_id' => 'wamid.LAST'))
  end
end
