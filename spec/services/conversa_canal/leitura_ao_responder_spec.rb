require 'rails_helper'

# #1865 — WhatsApp oficial e Híbrido: a resposta ao cliente marca a conversa como lida antes de sair (pela Cloud).
describe ConversaCanal::LeituraAoResponder do
  let(:account) { create(:account) }
  let(:canal) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |c|
      c.provider_config = { 'api_key' => 'chave', 'phone_number_id' => '123', 'business_account_id' => '777' }
      c.save!(validate: false)
    end
  end
  let(:caixa) { canal.inbox }
  let(:contato) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: '5511937016094') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: contact_inbox) }
  let(:meta_url) { 'https://graph.facebook.com/v24.0/123/messages' }
  let!(:recebida) do
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: 'wamid.ULTIMA',
                     created_at: 1.minute.ago)
  end

  def resposta(**attrs)
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, content: 'Oi', **attrs)
  end

  def lida_pedida?
    WebMock::RequestRegistry.instance.times_executed(
      WebMock::RequestPattern.new(:post, meta_url).with(body: hash_including('status' => 'read'))
    ).positive?
  end

  before do
    account.enable_features!('whatsapp_agenda_do_contato', 'conversa_cara_do_canal')
    stub_request(:post, meta_url).to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    allow(Rails.logger).to receive(:info)
    Redis::Alfred.scan_each(match: 'conversa_canal:leitura:mensagem:*') { |key| Redis::Alfred.delete(key) }
  end

  it 'marca a última recebida como lida e a resposta segue para o envio' do
    message = resposta
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(instance_double(Whatsapp::SendOnWhatsappService, perform: true))

    SendReplyJob.perform_now(message.id)

    expect(lida_pedida?).to be(true)
    expect(recebida.reload.content_attributes['read_receipt_sent_at']).to be_present
    expect(Whatsapp::SendOnWhatsappService).to have_received(:new).with(message: message)
  end

  it 'não marca para campanha, modelo aprovado nem nota privada' do
    described_class.marcar(resposta(additional_attributes: { 'campaign_id' => 3 }))
    described_class.marcar(resposta(additional_attributes: { 'template_params' => { 'name' => 'x' } }))
    described_class.marcar(resposta(private: true))

    expect(lida_pedida?).to be(false)
  end

  it 'sem a flag nada muda' do
    account.disable_features!('whatsapp_agenda_do_contato')

    described_class.marcar(resposta)

    expect(lida_pedida?).to be(false)
  end

  it 'Híbrido: contato por salvar só conta como trabalho quando a mensagem vai sair pelo WhatsApp API' do
    contato.update!(name: 'Celmo Junior')
    WhatsappHybrid::Connection.create!(account: account, inbox: caixa, session_name: 'hybrid-x', status: 'connected',
                                       connected_phone: canal.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    Redis::Alfred.delete('waha:agenda:hybrid-x:5511937016094@c.us')
    message = resposta
    router = instance_double(WhatsappHybrid::Router)
    allow(WhatsappHybrid::Router).to receive(:new).and_return(router)

    allow(router).to receive(:route_for).and_return(:cloud)
    expect(described_class.agenda_do_hibrido_a_fazer?(message)).to be(false)

    allow(router).to receive(:route_for).and_return(:web)
    expect(described_class.agenda_do_hibrido_a_fazer?(message)).to be(true)
  end

  it 'a falha da lida não impede a resposta' do
    message = resposta
    allow(ConversaCanal::LeituraNoCanal).to receive(:new).and_raise(StandardError)
    service = instance_double(Whatsapp::SendOnWhatsappService, perform: true)
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(service)

    SendReplyJob.perform_now(message.id)

    expect(service).to have_received(:perform)
  end
end
