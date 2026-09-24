require 'rails_helper'

# DEVOLVIDA À IA NÃO VOLTA SOZINHA PARA A EQUIPE (chat#612, 23/09/2026). Na conta 16, o operador desatribuía para devolver
# a conversa à Lia e, 34 segundos depois, a passagem reatribuía: a desatribuição dispara a avaliação, e a IA do CRM relia
# a fala antiga ("vou encaminhar para alguém da equipe") como pedido de agora. Seis devoluções seguidas, seis retornos.
RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:passagem) { 10.minutes.ago }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id => 'online' })
  end

  def build_card(ai_meta = { 'last_handoff_at' => passagem.iso8601, 'last_handoff_mode' => 'direct' })
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead devolvido', metadata: { 'ai' => ai_meta }
    )
  end

  def mensagem(tipo, quando, conteudo = 'oi')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo,
                     content: conteudo, created_at: quando)
  end

  def transferir(card)
    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'vai encaminhar' }).perform
  end

  it 'devolvida pelo humano e sem nada novo desde então, não reatribui' do
    mensagem(:outgoing, passagem - 1.minute, 'Vou encaminhar para alguém da equipe.')
    mensagem(:activity, 2.minutes.ago, 'Conversa desatribuída')

    result = transferir(build_card)

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('devolvida_sem_pedido_novo')
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'com um pedido novo depois da devolução, passa para a equipe de novo' do
    mensagem(:activity, 2.minutes.ago, 'Conversa desatribuída')
    mensagem(:incoming, 1.minute.ago, 'quero falar com uma pessoa')

    result = transferir(build_card)

    expect(result.status).to eq(:handed_off)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'a mensagem que veio antes da devolução não conta como pedido novo' do
    mensagem(:incoming, 5.minutes.ago, 'quero falar com uma pessoa')
    mensagem(:activity, 2.minutes.ago, 'Conversa desatribuída')

    expect(transferir(build_card).error).to eq('devolvida_sem_pedido_novo')
  end

  it 'nota privada depois da devolução não é pedido novo' do
    mensagem(:activity, 2.minutes.ago, 'Conversa desatribuída')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: 'nota interna', private: true, created_at: 1.minute.ago)

    expect(transferir(build_card).error).to eq('devolvida_sem_pedido_novo')
  end

  it 'sem passagem anterior, a primeira transferência acontece normalmente' do
    result = transferir(build_card({}))

    expect(result.status).to eq(:handed_off)
  end

  it 'o contexto da IA do CRM diz quando a conversa foi devolvida, e nada quando não foi' do
    devolucao = mensagem(:activity, 2.minutes.ago, 'Conversa desatribuída')

    card = build_card
    estado = Crm::Ai::ContextBuilder.new(card: card).perform[:conversation_state]
    expect(Time.zone.parse(estado[:returned_to_ai_at])).to be_within(1.second).of(devolucao.created_at)

    conversation.update!(assignee: agent)
    expect(Crm::Ai::ContextBuilder.new(card: card.reload).perform[:conversation_state][:returned_to_ai_at]).to be_nil
  end
end
