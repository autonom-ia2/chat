require 'rails_helper'

# O passo "mensagem" nos canais de verdade (#2414 F4): a janela de cada canal, lida como envio automático, e a mensagem
# sem remetente passando pelo envio do canal (SendReplyJob) sem erro.
RSpec.describe Autonomia::Automacao::PassoDeMensagem, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:passo) { mensagem_passo('p1', 'Seu pedido saiu.') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def rodar(conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, [passo]), conversa) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def recebida(conversa, quando)
    create(:message, conversation: conversa, account: conversa.account, inbox: conversa.inbox, message_type: :incoming,
                     content: 'oi', source_id: "in-#{SecureRandom.hex(3)}", created_at: quando)
  end

  def mandada(conversa) = conversa.messages.outgoing.where(private: false).last

  describe 'Instagram' do
    let(:canal) { create(:channel_instagram, account: account, instagram_id: 'instagram-123') }
    let(:contato) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contato, inbox: canal.inbox, source_id: 'ig-contato') }
    let(:conversa) { create(:conversation, account: account, contact: contato, inbox: canal.inbox, contact_inbox: contact_inbox) }
    let(:resposta) { instance_double(HTTParty::Response, success?: true, parsed_response: { 'message_id' => 'ig-mid-1' }) }

    before do
      InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: true)
      allow(HTTParty).to receive(:post).and_return(resposta)
    end

    it 'fora das 24 h pula com fora_da_janela, mesmo com a tag de agente humano (é envio automático)', :aggregate_failures do
      recebida(conversa, 30.hours.ago)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 pulado fora_da_janela]])
    end

    it 'dentro da janela, a mensagem sem remetente sai pelo canal sem erro', :aggregate_failures do
      recebida(conversa, 1.hour.ago)
      rodar(conversa)

      mensagem = mandada(conversa)
      expect(mensagem.sender).to be_nil
      SendReplyJob.perform_now(mensagem.id)

      expect(HTTParty).to have_received(:post).at_least(:once)
      expect(mensagem.reload.status).not_to eq('failed')
    end
  end

  describe 'WhatsApp Cloud' do
    let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:account) { canal.account }
    let(:contato) { create(:contact, account: account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: '5511937016094') }
    let(:conversa) { create(:conversation, inbox: canal.inbox, contact: contato, contact_inbox: contact_inbox, account: account) }

    before do
      stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' })
        .to_return(status: 200, body: { messages: [{ id: 'wamid.AUTOMACAO' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'dentro da janela, a mensagem sem remetente sai pela Cloud sem erro', :aggregate_failures do
      recebida(conversa, 1.hour.ago)
      rodar(conversa)

      mensagem = mandada(conversa)
      SendReplyJob.perform_now(mensagem.id)

      expect(mensagem.reload.source_id).to eq('wamid.AUTOMACAO')
      expect(mensagem.status).not_to eq('failed')
    end

    it 'fora da janela, sem caixa híbrida: pula', :aggregate_failures do
      recebida(conversa, 30.hours.ago)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 pulado fora_da_janela]])
    end

    context 'with a caixa híbrida pronta (WAHA)' do
      around { |exemplo| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { exemplo.run } }

      before do
        WhatsappHybrid::Connection.create!(
          account: account, inbox: canal.inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
          connected_phone: canal.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
        )
        WhatsappHybrid::Config.forget_inbox(canal.inbox.id)
      end

      it 'fora da janela oficial, manda: a resposta sai pelo WhatsApp API', :aggregate_failures do
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(conversa.whatsapp_api_reply?).to be(true)
        expect(mandada(conversa).content).to eq('Seu pedido saiu.')
        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      end
    end
  end
end
