require 'rails_helper'

# #1702 — lida no WhatsApp do cliente quando o atendente abre a conversa: uma vez por mensagem, só a última recebida.
describe ConversaCanal::LeituraNoCanal do
  let(:account) { create(:account) }

  before do
    account.enable_features!('conversa_cara_do_canal')
    allow(Rails.logger).to receive(:info)
  end

  after { Redis::Alfred.scan_each(match: 'conversa_canal:leitura:mensagem:*') { |key| Redis::Alfred.delete(key) } }

  def marcar(conversa, **)
    described_class.new(conversation: conversa, **).perform
  end

  context 'with WhatsApp oficial (Cloud API)' do
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
    let!(:anterior) { recebida('wamid.ANTERIOR', 2.minutes.ago) }
    let!(:ultima) { recebida('wamid.ULTIMA', 1.minute.ago) }

    def recebida(source_id, quando)
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: source_id,
                       created_at: quando)
    end

    before do
      stub_request(:post, meta_url).to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'marca só a última recebida, com o corpo da doc da Meta e o token no header' do
      marcar(conversa)

      expect(WebMock).to have_requested(:post, meta_url).once.with(
        headers: { 'Authorization' => 'Bearer chave' },
        body: { messaging_product: 'whatsapp', status: 'read', message_id: 'wamid.ULTIMA' }.to_json
      )
      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_present
      expect(anterior.reload.content_attributes['read_receipt_sent_at']).to be_nil
    end

    it 'deixa a marca de leitura do sistema até a mensagem marcada, para ela não voltar como leitura no celular (#2246)' do
      account.enable_features!(ConversaCanal::VistaNoCelular::FLAG)
      Redis::Alfred.delete(ConversaCanal::LeituraDoSistema.chave(conversa))

      marcar(conversa)

      expect(ConversaCanal::LeituraDoSistema.ate(conversa)).to eq(ultima.reload.created_at)
    end

    it 'não reenvia para a mesma mensagem' do
      marcar(conversa)
      marcar(conversa)

      expect(WebMock).to have_requested(:post, meta_url).once
    end

    it 'não envia enquanto outro job está com a mensagem reservada' do
      Redis::Alfred.set("conversa_canal:leitura:mensagem:#{ultima.id}", '1', nx: true, ex: 30)

      marcar(conversa)

      expect(WebMock).not_to have_requested(:post, meta_url)
    end

    it 'recusa da Meta solta a reserva: a próxima abertura manda de novo' do
      stub_request(:post, meta_url).to_return(status: 400, body: { error: { message: 'x' } }.to_json)
      marcar(conversa)
      marcar(conversa)

      expect(WebMock).to have_requested(:post, meta_url).twice
    end

    it 'marca de novo quando chega mensagem nova do cliente' do
      marcar(conversa)
      recebida('wamid.NOVA', Time.current)
      marcar(conversa)

      expect(WebMock).to have_requested(:post, meta_url).with(body: hash_including('message_id' => 'wamid.NOVA')).once
    end

    it 'ignora nota privada e mensagem enviada: olha a última recebida' do
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, private: true, content: 'nota')
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, source_id: 'wamid.ENVIADA')

      marcar(conversa)

      expect(WebMock).to have_requested(:post, meta_url).with(body: hash_including('message_id' => 'wamid.ULTIMA')).once
    end

    it 'não chama a Meta com a chave da conta desligada' do
      account.disable_features!('conversa_cara_do_canal')

      marcar(conversa)

      expect(WebMock).not_to have_requested(:post, meta_url)
    end

    it 'não chama a Meta para mensagem recebida há mais de 30 dias (limite da Meta)' do
      Message.where(id: [anterior.id, ultima.id]).update_all(created_at: 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      marcar(conversa)

      expect(WebMock).not_to have_requested(:post, meta_url)
    end

    it 'recusa da Meta: nada gravado, log info sem o token, e a próxima abertura tenta de novo' do
      stub_request(:post, meta_url).to_return(status: 400, body: { error: { message: 'chave' } }.to_json)

      marcar(conversa)

      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_nil
      expect(Rails.logger).to have_received(:info).with("[conversa_canal][leitura] cloud refused message=#{ultima.id} status=400")
      expect(described_class.new(conversation: conversa).pendente?).to be(true)
    end

    it 'Meta fora do ar: não levanta e não grava' do
      stub_request(:post, meta_url).to_raise(Net::OpenTimeout)

      expect { marcar(conversa) }.not_to raise_error
      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_nil
    end

    it 'não está pendente depois de marcada' do
      marcar(conversa)

      expect(described_class.new(conversation: conversa).pendente?).to be(false)
    end
  end

  context 'with caixa WhatsApp API (WAHA)' do
    let(:canal) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511888880000' }) }
    let(:caixa) { canal.inbox }
    let(:chat_id) { '5511999990000@c.us' }
    let(:contato) { create(:contact, account: account, custom_attributes: { 'waha_whatsapp_chat_id' => chat_id }) }
    let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato) }
    let(:seen_url) { 'https://waha.example/api/sendSeen' }
    let!(:ultima) do
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: 'false_5511999990000@c.us_3EB0')
    end

    around { |example| with_modified_env(WAHA_API_URL: 'https://waha.example', WAHA_API_KEY: 'waha-key') { example.run } }

    before do
      stub_request(:post, seen_url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')
    end

    it 'manda sendSeen do chat na sessão da caixa e grava uma vez' do
      marcar(conversa)
      marcar(conversa)

      expect(WebMock).to have_requested(:post, seen_url).once.with(
        headers: { 'X-Api-Key' => 'waha-key' }, body: { session: '5511888880000', chatId: chat_id }.to_json
      )
      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_present
    end

    it 'manda sendSeen mesmo quando o conector não gravou source_id na recebida' do
      ultima.update!(source_id: nil)

      marcar(conversa)

      expect(WebMock).to have_requested(:post, seen_url).once
      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_present
    end

    it 'não manda para grupo' do
      contato.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '120363000000000000@g.us' })

      marcar(conversa)

      expect(WebMock).not_to have_requested(:post, seen_url)
    end

    it 'recusa do motor: log info com classe e status, nada gravado' do
      stub_request(:post, seen_url).to_return(status: 500, body: 'falhou')

      marcar(conversa)

      expect(ultima.reload.content_attributes['read_receipt_sent_at']).to be_nil
      expect(Rails.logger).to have_received(:info)
        .with("[conversa_canal][leitura] waha refused conversation=#{conversa.id} Waha::Client::Error status=500")
    end

    it 'não chama o motor sem a WAHA configurada' do
      with_modified_env(WAHA_API_URL: '', WAHA_API_KEY: '') { marcar(conversa) }

      expect(WebMock).not_to have_requested(:post, seen_url)
    end
  end

  it 'canal fora do WhatsApp não está pendente' do
    conversa = create(:conversation, account: account, inbox: create(:inbox, account: account))
    create(:message, account: account, inbox: conversa.inbox, conversation: conversa, message_type: :incoming, source_id: 'x')

    expect(described_class.new(conversation: conversa).pendente?).to be(false)
  end
end
