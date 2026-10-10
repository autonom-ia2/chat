require 'rails_helper'

# Envio do resumo e do alerta (#1100, F4b): WAHA em texto livre, Oficial só com o modelo aprovado, sem criar
# contato nem conversa, e sem reenvio quando a resposta do WAHA não volta. Nenhum envio real.
RSpec.describe Crm::MetaAds::WhatsappReport::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:waha) { instance_double(Waha::Client) }
  let(:waha_inbox) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'vendas' }).inbox }
  let(:digest) do
    { date: Date.new(2026, 10, 6), currency: 'BRL', spend: 120.0, conversations: 8, cost_per_conversation: 15.0, quotes: 3, sales: 1,
      sales_value: 900.0, best_ad: { ad_id: '1', name: 'Promo outubro', conversations: 5 },
      action: { kind: 'stalled_quotes', source: 'rule', facts: { 'count' => 4, 'days' => 3, 'value' => 6200.0 } } }
  end
  let(:alert) { { ad_id: '1', name: 'Promo outubro', spend: 45.0, currency: 'BRL' } }

  def cloud_inbox(status: 'APPROVED')
    templates = [{ 'name' => 'chat2you_resumo_anuncios', 'language' => 'pt_BR', 'status' => status, 'namespace' => 'ns-1' },
                 { 'name' => 'chat2you_alerta_anuncio', 'language' => 'pt_BR', 'status' => status, 'namespace' => 'ns-2' }]
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511988887777', message_templates: templates,
                              sync_templates: false, validate_provider_config: false).inbox
  end

  def configure(inbox)
    connection.update!(whatsapp_report: { 'enabled' => true, 'inbox_id' => inbox.id }, whatsapp_report_phone: '+5511987654321')
  end

  def sender
    described_class.new(connection.reload)
  end

  def expect_code(code, &)
    expect(&).to raise_error(Crm::MetaAds::WhatsappReport::Settings::Error) { |error| expect(error.code).to eq(code) }
  end

  before do
    allow(Waha::Config).to receive(:enabled?).and_return(true)
    allow(Waha::Client).to receive(:new).and_return(waha)
    allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'WORKING', 'me' => { 'id' => '5511999990000@c.us' } })
  end

  describe 'WAHA' do
    before do
      configure(waha_inbox)
      allow(waha).to receive(:check_contact_exists).with(phone: '5511987654321', session: 'vendas')
                                                   .and_return({ 'numberExists' => true, 'chatId' => '551187654321@c.us' })
      allow(waha).to receive(:new_message_id).with('vendas').and_return('msg-1')
    end

    it 'manda texto livre ao chat que o WhatsApp devolveu, sem criar contato nem conversa' do
      allow(waha).to receive(:send_text).and_return({ 'id' => 'msg-1' })

      expect { sender.send_summary(digest) }.not_to(change { [Contact.count, Conversation.count, Message.count] })

      expect(waha).to have_received(:send_text) do |session:, chat_id:, text:, id:|
        expect([session, chat_id, id]).to eq(['vendas', '551187654321@c.us', 'msg-1'])
        expect(text).to eq(<<~TEXT.chomp)
          Anúncios da Meta — ontem, 06/10
          Investido: R$ 120,00
          Conversas: 8 (R$ 15,00 por conversa)
          Propostas: 3 · Vendas: 1 (R$ 900,00)
          Melhor anúncio: Promo outubro, com 5 conversas
          O que fazer hoje: Retome as 4 propostas paradas há mais de 3 dias (R$ 6.200).
          Ver o painel: /app/accounts/#{account.id}/campaigns/meta-ads?aba=resultado
        TEXT
      end
    end

    it 'teste leva o prefixo e o alerta diz o anúncio e o gasto' do
      texts = []
      allow(waha).to receive(:send_text) { |text:, **| texts << text }

      sender.send_summary(digest, test: true)
      sender.send_alert(alert)

      expect(texts.size).to eq(2)
      expect(texts.first).to start_with('[Teste] Anúncios da Meta — ontem, 06/10')
      expect(texts.last).to start_with('Atenção: o anúncio Promo outubro gastou R$ 45,00 hoje e ainda não trouxe nenhuma conversa.')
    end

    it 'sem resposta do envio vira send_uncertain e não tenta de novo' do
      allow(waha).to receive(:send_text).and_raise(Waha::Client::Timeout, 'sem resposta')

      expect_code('send_uncertain') { sender.send_summary(digest) }
      expect(waha).to have_received(:send_text).once
    end

    it 'erro do motor vira send_failed; número sem WhatsApp vira whatsapp_number_not_found' do
      allow(waha).to receive(:send_text).and_raise(Waha::Client::Error, 'WAHA POST /api/sendText -> 500')
      expect_code('send_failed') { sender.send_summary(digest) }

      allow(waha).to receive(:check_contact_exists).and_return({ 'numberExists' => false })
      expect_code('whatsapp_number_not_found') { sender.send_summary(digest) }
    end

    it 'timeout antes do envio é falha clara' do
      allow(waha).to receive(:check_contact_exists).and_raise(Waha::Client::Timeout, 'sem resposta')
      allow(waha).to receive(:send_text)

      expect_code('send_failed') { sender.send_summary(digest) }
      expect(waha).not_to have_received(:send_text)
    end

    it 'sessão que caiu deixa de ser origem na hora do envio' do
      allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'STOPPED' })
      allow(waha).to receive(:send_text)

      expect_code('inbox_not_connected') { sender.send_summary(digest) }
      expect(waha).not_to have_received(:send_text)
    end
  end

  describe 'Oficial' do
    def stub_cloud_send(status: 200, body: { messages: [{ id: 'wamid.1' }] })
      stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/messages') })
        .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'manda o modelo aprovado em pt_BR com os números nas variáveis' do
      configure(cloud_inbox)
      request = stub_cloud_send

      sender.send_summary(digest)

      expect(request).to have_been_made.once
      body = nil
      expect(a_request(:post, ->(uri) { uri.path.end_with?('/messages') }).with { |req| body = JSON.parse(req.body) }).to have_been_made
      template = body['template']
      expect(body['to']).to eq('5511987654321')
      expect(template['name']).to eq('chat2you_resumo_anuncios')
      expect(template['language']).to eq('policy' => 'deterministic', 'code' => 'pt_BR')
      expect(template['components'].sole['parameters'].pluck('text'))
        .to eq(['06/10', 'R$ 120,00', '8 conversas, 3 propostas e 1 venda', 'Retome as 4 propostas paradas há mais de 3 dias (R$ 6.200).'])
    end

    it 'sem o modelo aprovado não envia; recusa do provedor é send_failed' do
      configure(cloud_inbox(status: 'PENDING'))
      request = stub_cloud_send(status: 400, body: { error: { message: 'erro', code: 132_000 } })

      expect_code('template_not_approved') { sender.send_alert(alert) }
      expect(request).not_to have_been_made

      connection.update!(whatsapp_report: connection.whatsapp_report_settings.merge('inbox_id' => cloud_inbox_approved.id))
      expect_code('send_failed') { sender.send_alert(alert) }
      expect(request).to have_been_made.once
    end

    it 'conexão que cai no meio do envio pode ter mandado: send_uncertain; recusa antes de conectar é send_failed' do
      configure(cloud_inbox)
      [Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, Errno::EPIPE, OpenSSL::SSL::SSLError].each do |error|
        stub_request(:post, ->(uri) { uri.path.end_with?('/messages') }).to_raise(error)
        expect_code('send_uncertain') { sender.send_summary(digest) }
      end

      stub_request(:post, ->(uri) { uri.path.end_with?('/messages') }).to_raise(Errno::ECONNREFUSED)
      expect_code('send_failed') { sender.send_summary(digest) }
    end
  end

  def cloud_inbox_approved
    templates = [{ 'name' => 'chat2you_alerta_anuncio', 'language' => 'pt_BR', 'status' => 'APPROVED', 'namespace' => 'ns-2' }]
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511977776666', message_templates: templates,
                              sync_templates: false, validate_provider_config: false).inbox
  end
end
