require 'rails_helper'

# Resposta nossa marca a conversa como vista (#2202, PR 0): como no WhatsApp, se eu respondi, já li.
# As mensagens do cliente nascem num segundo e as respostas em outro: o "visto" vai até o começo do segundo da resposta.
RSpec.describe ConversaCanal::VistaAoResponder do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, agent_last_seen_at: inicio - 1.hour) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:inicio) { Time.zone.parse('2026-10-26 10:00:00') }

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    conversation
  end

  after { Current.reset }

  def do_cliente(segundos = 0, content: 'Oi, tudo bem?')
    travel_to(inicio + segundos) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       sender: conversation.contact, content: content)
    end
  end

  def nossa(segundos = 10, sender: ana, **attrs)
    travel_to(inicio + segundos) do
      message = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                content: 'Tudo, e você?', **attrs)
      message.sender = sender
      message.save!
      message
    end
  end

  def eco(segundos = 10)
    nossa(segundos, sender: nil, content_attributes: { 'external_echo' => true })
  end

  def nao_lidas
    conversation.reload.unread_incoming_messages.count
  end

  def eventos_de_lida
    Rails.configuration.dispatcher
  end

  describe 'resposta nossa e pública' do
    before do
      do_cliente(0)
      do_cliente(1)
    end

    it 'pelo painel zera a não lida', :aggregate_failures do
      Current.user = ana
      expect(nao_lidas).to eq(2)

      nossa

      expect(nao_lidas).to eq(0)
      expect(conversation.reload.agent_last_seen_at).to eq(inicio + 10.seconds - Rational(1, 1_000_000))
    end

    # Decisão do Rodrigo (#2202, opção B): nenhum canal diz se o eco foi uma pessoa digitando, resposta automática do
    # celular ou robô mandando direto pela WAHA. Sem remetente (Cloud, Híbrido) ou com o dono do token do conector
    # como remetente (WAHA comum), o eco não apaga.
    it 'eco não apaga', :aggregate_failures do
      eco(10)
      expect(nao_lidas).to eq(2)

      nossa(20, sender: ana, content_attributes: { 'external_echo' => true })
      expect(nao_lidas).to eq(2)
    end

    it 'modelo do WhatsApp mandado na conversa zera' do
      nossa(additional_attributes: { 'template_params' => { 'name' => 'boas_vindas' } })

      expect(nao_lidas).to eq(0)
    end
  end

  describe 'o que sai sem ninguém responder nesta conversa' do
    before { do_cliente }

    it 'nota privada não zera' do
      nossa(private: true)

      expect(nao_lidas).to eq(1)
    end

    it 'campanha não zera', :aggregate_failures do
      nossa(additional_attributes: { 'campaign_id' => 7 })
      nossa(additional_attributes: { 'whatsapp_api_campaign_id' => 8 })

      expect(nao_lidas).to eq(1)
    end

    it 'envio automático em nome de alguém (automação, follow-up) não zera', :aggregate_failures do
      nossa(content_attributes: { 'automation_rule_id' => 1 })
      nossa(content_attributes: { 'crm_follow_up_id' => 2 })

      expect(nao_lidas).to eq(1)
    end

    it 'pesquisa de satisfação que sai como mensagem (WhatsApp) não zera' do
      nossa(sender: nil, content_type: :input_csat, content: 'Avalie o atendimento')

      expect(nao_lidas).to eq(1)
    end

    it 'cópia encaminhada de outra conversa não zera' do
      nossa(content_attributes: { 'forwarded' => true, 'forwarded_from' => { 'conversation_id' => 1, 'message_id' => 2 } })

      expect(nao_lidas).to eq(1)
    end

    it 'modelo reenviado no encaminhamento não zera' do
      nossa(content_attributes: { 'reenvio_do_modelo' => { 'mensagem_original_id' => 3 } })

      expect(nao_lidas).to eq(1)
    end

    it 'mensagem que falhou não zera' do
      nossa(status: :failed)

      expect(nao_lidas).to eq(1)
    end
  end

  describe 'até onde fica vista' do
    it 'mensagem do cliente depois da nossa volta a contar', :aggregate_failures do
      do_cliente(0)
      nossa(10)
      expect(nao_lidas).to eq(0)

      do_cliente(20, content: 'E aí?')

      expect(nao_lidas).to eq(1)
    end

    it 'mensagem do cliente no mesmo segundo da resposta continua não lida, no servidor e na tela', :aggregate_failures do
      mesmo_instante = inicio + 10.5.seconds
      cliente = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                 sender: conversation.contact, created_at: mesmo_instante)
      resposta = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                 created_at: mesmo_instante)
      resposta.sender = ana
      resposta.save!

      expect(nao_lidas).to eq(1)
      # A tela compara segundos inteiros (getters.js getUnreadCount, conversationHelper.js getUnreadMessages).
      expect(conversation.reload.agent_last_seen_at.to_i).to be < cliente.created_at.to_i
    end

    it 'nunca volta o "visto" para trás (a leitura no painel mais nova fica)' do
      do_cliente(0)
      visto = inicio + 1.hour
      conversation.update_columns(agent_last_seen_at: visto) # rubocop:disable Rails/SkipsModelValidations

      nossa(30)

      expect(conversation.reload.agent_last_seen_at).to eq(visto)
    end
  end

  # Decisão do Rodrigo (#2202): só resposta de pessoa apaga a bolinha.
  describe 'robô' do
    before { do_cliente(0) }

    it 'robô não apaga' do
      nossa(10, sender: bot)

      expect(nao_lidas).to eq(1)
    end

    it 'saída sem remetente não apaga' do
      nossa(10, sender: nil)

      expect(nao_lidas).to eq(1)
    end

    it 'robô responde e depois a pessoa responde: apaga', :aggregate_failures do
      nossa(10, sender: bot)
      expect(nao_lidas).to eq(1)

      nossa(20, sender: ana)

      expect(nao_lidas).to eq(0)
    end

    # O token de integração (MCP, CRM) entra como um usuário sintético da conta, com account_users.integration = true
    # (Mcp::IntegrationToken#create_managed_user): o remetente é User, mas não é uma pessoa.
    it 'usuário de integração (MCP, CRM) não apaga' do
      sintetico = create(:user, name: 'MCP Integration (teste)')
      AccountUser.create!(account: account, user: sintetico, role: :agent, integration: true)

      nossa(10, sender: sintetico)

      expect(nao_lidas).to eq(1)
    end

    it 'mensagem automática da caixa (message_type template) não apaga' do
      travel_to(inicio + 10) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :template,
                         sender: nil, content: 'Estamos fora do horário')
      end

      expect(nao_lidas).to eq(1)
    end
  end

  describe 'avisos' do
    before do
      do_cliente
      Current.user = ana
      allow(eventos_de_lida).to receive(:dispatch).and_call_original
    end

    it 'sai o conversation.read com a conversa já vista, para a lista apagar a bolinha', :aggregate_failures do
      nossa

      expect(eventos_de_lida).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_READ, anything, hash_including(conversation: conversation))
      expect(ActionCableBroadcastJob).to have_been_enqueued
        .with(array_including(ana.pubsub_token), Events::Types::CONVERSATION_READ, hash_including(id: conversation.display_id))
    end

    it 'o message.created da resposta já leva a não lida zerada' do
      resposta = nossa

      expect(ActionCableBroadcastJob).to have_been_enqueued
        .with(anything, Events::Types::MESSAGE_CREATED, hash_including(id: resposta.id, conversation: hash_including(unread_count: 0)))
    end

    it 'resposta em sequência não refaz a contagem' do
      nossa(10)
      nossa(20)

      expect(eventos_de_lida).to have_received(:dispatch).with(Events::Types::CONVERSATION_READ, anything, anything).once
    end

    it 'nota privada não manda o evento' do
      nossa(private: true)

      expect(eventos_de_lida).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_READ, anything, anything)
    end

    it 'marca como lidos os avisos do sino desta conversa só de quem respondeu', :aggregate_failures do
      bruno = create(:user, account: account, role: :agent)
      da_ana = create(:notification, user: ana, account: account, primary_actor: conversation)
      do_bruno = create(:notification, user: bruno, account: account, primary_actor: conversation)

      nossa

      expect(da_ana.reload.read_at).to be_present
      expect(do_bruno.reload.read_at).to be_nil
    end

    it 'não marca os avisos do sino quando o "visto" não anda' do
      aviso = create(:notification, user: ana, account: account, primary_actor: conversation)
      conversation.update_columns(agent_last_seen_at: inicio + 1.hour) # rubocop:disable Rails/SkipsModelValidations

      nossa

      expect(aviso.reload.read_at).to be_nil
    end

    it 'o eco não marca os avisos do sino de ninguém' do
      aviso = create(:notification, user: ana, account: account, primary_actor: conversation)

      nossa(sender: ana, content_attributes: { 'external_echo' => true })

      expect(aviso.reload.read_at).to be_nil
    end
  end

  describe 'falha ao marcar' do
    before do
      do_cliente
      allow(described_class).to receive(:marcar!).and_raise(ActiveRecord::StatementInvalid, 'boom')
    end

    it 'no teste, o erro sobe' do
      expect { nossa }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'fora do teste, não impede o envio e vai para o log e o rastreador', :aggregate_failures do
      allow(described_class).to receive(:relancar?).and_return(false)
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original
      allow(Rails.logger).to receive(:error).and_call_original

      resposta = nil
      expect { resposta = nossa }.to have_enqueued_job(SendReplyJob)

      expect(resposta).to be_persisted
      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::StatementInvalid), account: account)
      expect(Rails.logger).to have_received(:error).with(include('[conversa][vista_ao_responder]', 'StatementInvalid: boom'))
    end

    it 'se o próprio registro da falha quebrar, não sobe, o envio sai e o outro canal registra', :aggregate_failures do
      allow(described_class).to receive(:relancar?).and_return(false)
      allow(Rails.logger).to receive(:error).and_raise(IOError, 'log fora')
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      resposta = nil
      expect { resposta = nossa }.to have_enqueued_job(SendReplyJob)

      expect(resposta).to be_persisted
      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::StatementInvalid), account: account)
    end

    it 'com o log e o rastreador quebrados, ainda assim não sobe e o envio sai', :aggregate_failures do
      allow(described_class).to receive(:relancar?).and_return(false)
      allow(Rails.logger).to receive(:error).and_raise(IOError, 'log fora')
      allow(ChatwootExceptionTracker).to receive(:new).and_raise(SocketError, 'rastreador fora')

      resposta = nil
      expect { resposta = nossa }.to have_enqueued_job(SendReplyJob)

      expect(resposta).to be_persisted
    end
  end
end
