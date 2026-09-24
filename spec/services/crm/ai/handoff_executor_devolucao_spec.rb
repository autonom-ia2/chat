require 'rails_helper'

# DEVOLVIDA À IA NÃO VOLTA SOZINHA PARA A EQUIPE (chat#632, 23/09/2026). Na conta 16, o operador desatribuía para devolver
# a conversa à Lia e, 34 segundos depois, a passagem reatribuía: a desatribuição dispara a avaliação, e a IA do CRM relia
# a fala antiga ("vou encaminhar para alguém da equipe") como pedido de agora. Seis devoluções seguidas, seis retornos.
RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:passagem) { 10.minutes.ago }
  let(:devolucao) { 5.minutes.ago }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id => 'online' })
  end

  def build_card(ai_meta = { 'last_handoff_at' => passagem.iso8601, 'last_handoff_mode' => 'direct' }, mode: 'r2_direct')
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => mode } })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead devolvido', metadata: { 'ai' => ai_meta }
    )
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
    card
  end

  def devolvido(card)
    Crm::Ai::DevolucaoAIa.registrar!(conversation, devolucao)
    card.reload
  end

  def mensagem(tipo, quando, conteudo = 'oi', **extra)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo,
                     content: conteudo, created_at: quando, **extra)
  end

  def transferir(card)
    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'vai encaminhar' }).perform
  end

  it 'devolvida pelo humano e sem nada novo desde então, não reatribui' do
    mensagem(:outgoing, passagem - 1.minute, 'Vou encaminhar para alguém da equipe.', sender: agent_bot)

    result = transferir(devolvido(build_card))

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('devolvida_sem_pedido_novo')
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'com um pedido novo do cliente depois da devolução, passa para a equipe de novo' do
    card = devolvido(build_card)
    mensagem(:incoming, 1.minute.ago, 'quero falar com uma pessoa')

    expect(transferir(card).status).to eq(:handed_off)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'o agente de IA encaminhando de novo depois da devolução também é pedido novo' do
    card = devolvido(build_card)
    mensagem(:outgoing, 1.minute.ago, 'Vou encaminhar para alguém da equipe.', sender: agent_bot)

    expect(transferir(card).status).to eq(:handed_off)
  end

  it 'uma atividade depois do pedido (etiqueta, reabertura) não apaga o pedido' do
    card = devolvido(build_card)
    mensagem(:incoming, 2.minutes.ago, 'quero falar com uma pessoa')
    mensagem(:activity, 1.minute.ago, 'Conversa reaberta')

    expect(transferir(card).status).to eq(:handed_off)
  end

  it 'a fala do próprio atendente e a nota privada depois da devolução não são pedido' do
    card = devolvido(build_card)
    mensagem(:outgoing, 2.minutes.ago, 'A Lia segue com você.', sender: agent)
    mensagem(:outgoing, 1.minute.ago, 'nota interna', private: true)

    expect(transferir(card).error).to eq('devolvida_sem_pedido_novo')
  end

  it 'a mensagem que veio antes da devolução não conta como pedido novo' do
    mensagem(:incoming, 7.minutes.ago, 'quero falar com uma pessoa')

    expect(transferir(devolvido(build_card)).error).to eq('devolvida_sem_pedido_novo')
  end

  it 'sem passagem anterior, a primeira transferência acontece normalmente e nada é carimbado' do
    card = devolvido(build_card({}))

    expect(card.metadata.dig('ai', Crm::Ai::DevolucaoAIa::CHAVE)).to be_nil
    expect(transferir(card).status).to eq(:handed_off)
  end

  it 'no convite a conversa nunca foi de ninguém: não há devolução' do
    card = devolvido(build_card({ 'last_handoff_at' => passagem.iso8601, 'last_handoff_mode' => 'invite' }))

    expect(card.metadata.dig('ai', Crm::Ai::DevolucaoAIa::CHAVE)).to be_nil
    expect(Crm::Ai::DevolucaoAIa.em(card, conversation)).to be_nil
  end

  it 'uma passagem nova depois da devolução volta a valer' do
    card = devolvido(build_card)
    card.update!(metadata: card.metadata.deep_merge('ai' => { 'last_handoff_at' => 1.minute.ago.iso8601 }))

    expect(Crm::Ai::DevolucaoAIa.em(card, conversation)).to be_nil
  end

  it 'o contexto da IA do CRM diz quando a conversa foi devolvida, e nada quando ela está com alguém' do
    card = devolvido(build_card)

    estado = Crm::Ai::ContextBuilder.new(card: card).perform[:conversation_state]
    expect(Time.zone.parse(estado[:returned_to_ai_at])).to be_within(1.second).of(devolucao)

    conversation.update!(assignee: agent)
    expect(Crm::Ai::ContextBuilder.new(card: card.reload).perform[:conversation_state][:returned_to_ai_at]).to be_nil
  end

  it 'o carimbo é da conversa devolvida: outra conversa do mesmo card não é bloqueada por ele' do
    card = devolvido(build_card)
    outra = create_crm_conversation(account: account, inbox: inbox, contact: contact)

    expect(Crm::Ai::DevolucaoAIa.em(card, outra)).to be_nil
  end

  it 'card ligado só pela conversa primária também é carimbado' do
    card = build_card
    Crm::CardConversation.where(card: card).delete_all

    expect(devolvido(card).metadata.dig('ai', Crm::Ai::DevolucaoAIa::CHAVE)).to be_present
  end

  it 'a avaliação que já estava rodando não apaga o carimbo gravado enquanto ela esperava o modelo' do
    card = build_card
    avaliacao = Crm::Ai::Evaluator.new(card: Crm::Card.find(card.id))
    Crm::Ai::DevolucaoAIa.registrar!(conversation, devolucao)

    avaliacao.send(:touch_evaluation_metadata, { model_used: 'modelo' })

    expect(card.reload.metadata.dig('ai', Crm::Ai::DevolucaoAIa::CHAVE)).to be_present
    expect(card.metadata.dig('ai', 'last_model_used')).to eq('modelo')
  end

  it 'a desatribuição carimba a devolução antes de enfileirar a avaliação do card' do
    card = build_card
    evento = Events::Base.new('assignee.changed', Time.zone.now, conversation: conversation)

    Crm::ConversationObserverListener.instance.assignee_changed(evento)

    expect(card.reload.metadata.dig('ai', Crm::Ai::DevolucaoAIa::CHAVE)).to be_present
  end
end
