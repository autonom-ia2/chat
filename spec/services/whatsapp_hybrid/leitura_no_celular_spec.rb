require 'rails_helper'

# #2246 no Híbrido: o celular do negócio lê a mensagem do cliente, o motor (GOWS) avisa a sessão auxiliar com um
# message.ack fromMe=false, e o "visto" do agente anda até a mensagem lida. Payload anonimizado, no formato que o
# controller entrega ao job (WhatsappHybrid::WebhookEventJob).
describe WhatsappHybrid::LeituraNoCelular do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-leitura', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
  end
  # Amostra do spike F0 (spec do Wamid): wamid de mensagem recebida, com o id físico dentro.
  let(:wamid) { 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFDJBNUQyRDhEQTA4OUJFNDJFNEQ1AA==' }
  let(:physical_id) { '2A5D2D8DA089BE42E4D5' }
  let(:inicio) { Time.zone.parse('2026-10-27 10:00:00') }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, agent_last_seen_at: inicio - 1.hour)
  end

  def recebida(segundos, source_id: "wamid.OUTRA#{segundos}")
    travel_to(inicio + segundos) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       sender: contact, source_id: source_id)
    end
  end

  def ack(overrides = {})
    { 'id' => "false_5511937016094@c.us_#{physical_id}", 'ack' => 3, 'from_me' => false, 'aparelho' => '0' }.merge(overrides)
  end

  def aplicar(payload = ack)
    described_class.new(connection).aplicar(payload)
  end

  def nao_lidas
    conversation.reload.unread_incoming_messages.count
  end

  before do
    account.enable_features!(ConversaCanal::VistaNoCelular::FLAG)
    connection
    Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))
    Redis::Alfred.delete(ConversaCanal::LeituraDoSistema.chave(conversation))
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  after do
    Redis::Alfred.delete(described_class.chave(inbox.id, physical_id))
    Redis::Alfred.delete(ConversaCanal::LeituraDoSistema.chave(conversation))
  end

  describe '.aparelho' do
    it 'devolve só o número do aparelho, e 0 quando o endereço não traz aparelho' do
      expect(described_class.aparelho('5511999990000:3@s.whatsapp.net')).to eq('3')
      expect(described_class.aparelho('5511999990000@s.whatsapp.net')).to eq('0')
      expect(described_class.aparelho('123456789012345:0@lid')).to eq('0')
      expect(described_class.aparelho(nil)).to be_nil
    end
  end

  describe 'chegada da mensagem pela Cloud' do
    def entregar
      params = { phone_number: channel.phone_number, object: 'whatsapp_business_account',
                 entry: [{ changes: [{ value: { contacts: [{ profile: { name: 'Cliente' }, wa_id: '5511937016094' }],
                                                messages: [{ from: '5511937016094', id: wamid, timestamp: '1667047370',
                                                             type: 'text', text: { body: 'Oi' } }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
      inbox.messages.reload.last
    end

    after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

    it 'guarda o id físico da recebida apontando para a mensagem' do
      mensagem = entregar

      expect(Redis::Alfred.get(described_class.chave(inbox.id, physical_id))).to eq(mensagem.id.to_s)
    end

    it 'não guarda nada sem a flag' do
      account.disable_features!(ConversaCanal::VistaNoCelular::FLAG)

      entregar

      expect(Redis::Alfred.get(described_class.chave(inbox.id, physical_id))).to be_nil
    end

    it 'não guarda nada numa caixa oficial sem Híbrido' do
      connection.destroy!
      Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))

      entregar

      expect(Redis::Alfred.get(described_class.chave(inbox.id, physical_id))).to be_nil
    end
  end

  describe 'leitura feita no celular' do
    let!(:lida) { recebida(0, source_id: wamid) }

    before do
      recebida(5)
      described_class.indexar(lida)
    end

    it 'anda o visto até o fim do segundo da mensagem lida, sem marcar as que chegaram depois', :aggregate_failures do
      expect(nao_lidas).to eq(2)

      expect(aplicar).to be(true)

      expect(conversation.reload.agent_last_seen_at).to eq(inicio + 1.second - Rational(1, 1_000_000))
      expect(nao_lidas).to eq(1)
    end

    it 'avisa a tela e os contadores, sem marcar o sino de ninguém' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      expect(Notification::MarkConversationReadService).not_to receive(:new)

      aplicar

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_READ, anything, hash_including(conversation: conversation))
    end

    it 'vale também para o ack de ouvido (4)' do
      expect(aplicar(ack('ack' => 4))).to be(true)
    end

    it 'nunca anda o visto para trás' do
      conversation.update_columns(agent_last_seen_at: inicio + 1.minute) # rubocop:disable Rails/SkipsModelValidations

      expect(aplicar).to be(false)
      expect(conversation.reload.agent_last_seen_at).to eq(inicio + 1.minute)
    end

    it 'não conta leitura de aparelho vinculado (WhatsApp Web, a Cloud, outra automação)' do
      expect(aplicar(ack('aparelho' => '2'))).to be(false)
      expect(nao_lidas).to eq(2)
    end

    it 'não conta ack sem o aparelho que leu' do
      expect(aplicar(ack.except('aparelho'))).to be(false)
      expect(nao_lidas).to eq(2)
    end

    it 'não conta leitura logo depois de uma lida mandada pelo próprio sistema (robô respondendo)' do
      ConversaCanal::LeituraDoSistema.registrar(conversation)

      expect(aplicar).to be(false)
      expect(nao_lidas).to eq(2)
    end

    it 'não conta ack de entrega (2)' do
      expect(aplicar(ack('ack' => 2))).to be(false)
    end

    it 'não faz nada sem a flag' do
      account.disable_features!(ConversaCanal::VistaNoCelular::FLAG)

      expect(aplicar).to be(false)
      expect(nao_lidas).to eq(2)
    end

    it 'ignora id físico que não é de mensagem recebida conhecida' do
      expect(aplicar(ack('id' => 'false_5511937016094@c.us_DESCONHECIDO'))).to be(false)
    end
  end
end
