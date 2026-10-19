require 'rails_helper'

# #1865 — caixa WAHA comum: antes de o webhook mandar a mensagem ao conector, o contato vai para a agenda do aparelho e a
# resposta marca a conversa como lida.
describe Waha::AntesDoEnvio do
  let(:account) { create(:account) }
  let(:canal) do
    create(:channel_api, account: account, webhook_url: 'https://waha.example/webhooks/chatwoot/s/1',
                         additional_attributes: { 'provider' => 'waha', 'session' => '5511888880000' })
  end
  let(:caixa) { canal.inbox }
  let(:contato) do
    create(:contact, account: account, name: 'Patricia Stephane', phone_number: '+5511991177389',
                     custom_attributes: { 'waha_whatsapp_chat_id' => '5511991177389@c.us' })
  end
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato) }
  let(:agente) { create(:user, account: account) }
  let(:base) { 'https://waha.example' }
  let(:contato_url) { "#{base}/api/contacts?contactId=5511991177389%40c.us&session=5511888880000" }
  let(:salvar_url) { "#{base}/api/5511888880000/contacts/5511991177389@c.us" }
  let(:seen_url) { "#{base}/api/sendSeen" }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def payload_de(message)
    { event: 'message_created', id: message.id, message_type: 'outgoing', private: false }
  end

  def resposta(**attrs)
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, sender: agente,
                     content: 'Oi', **attrs)
  end

  around { |example| with_modified_env(WAHA_API_URL: base, WAHA_API_KEY: 'waha-key') { example.run } }

  before do
    account.enable_features!('whatsapp_agenda_do_contato', 'conversa_cara_do_canal')
    stub_request(:get, contato_url).to_return(status: 200, headers: json, body: { name: '', pushname: 'Pat' }.to_json)
    stub_request(:put, salvar_url).to_return(status: 200, headers: json, body: { success: true }.to_json)
    stub_request(:post, seen_url).to_return(status: 200, headers: json, body: '{}')
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: 'Olá', created_at: 1.minute.ago)
    Redis::Alfred.delete('waha:agenda:5511888880000:5511991177389@c.us')
    Redis::Alfred.scan_each(match: 'conversa_canal:leitura:mensagem:*') { |key| Redis::Alfred.delete(key) }
    Redis::Alfred.delete("conversa_canal:envio_em_ordem:#{conversa.id}")
  end

  it 'o webhook sai sempre, mesmo quando a mensagem não é da caixa WAHA' do
    saiu = false
    described_class.em_ordem({ event: 'message_created', id: 0, message_type: 'outgoing' }) { saiu = true }

    expect(saiu).to be(true)
  end

  it 'salva o contato e marca a conversa como lida antes de o webhook levar a resposta ao conector' do
    message = resposta
    ordem = []
    allow(Webhooks::Trigger).to receive(:execute) { ordem << :webhook }
    WebMock.after_request { |req, _| ordem << req.method if req.uri.to_s.start_with?(base) }

    WebhookJob.perform_now(canal.webhook_url, payload_de(message), :api_inbox_webhook)

    expect(WebMock).to have_requested(:put, salvar_url).with(body: { firstName: 'Patricia', lastName: 'Stephane' }.to_json)
    expect(WebMock).to have_requested(:post, seen_url).once
    expect(ordem.last).to eq(:webhook)
    expect(ordem.count(:webhook)).to eq(1)
  ensure
    WebMock::CallbackRegistry.reset
  end

  it 'campanha salva o contato mas não marca como lida' do
    described_class.em_ordem(payload_de(resposta(additional_attributes: { 'whatsapp_api_campaign_id' => 7 }))) { nil }

    expect(WebMock).to have_requested(:put, salvar_url)
    expect(WebMock).not_to have_requested(:post, seen_url)
  end

  it 'sem a flag não chama o motor' do
    account.disable_features!('whatsapp_agenda_do_contato')

    described_class.em_ordem(payload_de(resposta)) { nil }

    expect(WebMock).not_to have_requested(:get, contato_url)
    expect(WebMock).not_to have_requested(:post, seen_url)
  end

  it 'ignora nota privada, mensagem recebida e outros eventos' do
    message = resposta
    described_class.em_ordem(payload_de(message).merge(private: true)) { nil }
    described_class.em_ordem(payload_de(message).merge(message_type: 'incoming')) { nil }
    described_class.em_ordem(payload_de(message).merge(event: 'message_updated')) { nil }

    expect(WebMock).not_to have_requested(:get, contato_url)
  end

  it 'falha do motor não impede o webhook' do
    message = resposta
    stub_request(:get, contato_url).to_timeout
    stub_request(:post, seen_url).to_timeout
    allow(Rails.logger).to receive(:info)
    allow(Webhooks::Trigger).to receive(:execute)

    WebhookJob.perform_now(canal.webhook_url, payload_de(message), :api_inbox_webhook)

    expect(WebMock).to have_requested(:get, contato_url)
    expect(Webhooks::Trigger).to have_received(:execute)
      .with(canal.webhook_url, payload_de(message), :api_inbox_webhook, secret: nil, delivery_id: nil)
  end

  it 'conversa de grupo não toca a agenda' do
    contato.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '120363000000000000@g.us' })

    described_class.em_ordem(payload_de(resposta)) { nil }

    expect(WebMock).not_to have_requested(:get, contato_url)
  end

  it 'sem a lida do #1702 (conversa_cara_do_canal), salva o contato mas não marca como lida' do
    account.disable_features!('conversa_cara_do_canal')

    described_class.em_ordem(payload_de(resposta)) { nil }

    expect(WebMock).to have_requested(:put, salvar_url)
    expect(WebMock).not_to have_requested(:post, seen_url)
  end

  it 'o WebhookJob da caixa passa por aqui antes de entregar; os outros tipos de webhook não' do
    message = resposta
    allow(Webhooks::Trigger).to receive(:execute)

    WebhookJob.perform_now(canal.webhook_url, payload_de(message), :api_inbox_webhook)
    WebhookJob.perform_now('https://outro.example', payload_de(message), :account_webhook)

    expect(WebMock).to have_requested(:put, salvar_url).once
    expect(Webhooks::Trigger).to have_received(:execute).twice
  end
end
