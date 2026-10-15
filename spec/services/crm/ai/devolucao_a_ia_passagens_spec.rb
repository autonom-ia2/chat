require 'rails_helper'

# #1606 (corrida a): o pedido de pessoa já atendido e devolvido não volta para a equipe. Antes, só a passagem direta
# pela regra do funil carimbava a devolução; o convite aceito, a entrega sem regra e a atribuição pela tela não, e a IA
# do CRM relia "quero falar com alguém" como pedido de agora. Agora a devolução vem do registro de passagens, e o
# classificador lê as passagens recentes. Sem trava por tempo: vale "nada novo desde a devolução" e o que o modelo lê.
RSpec.describe Crm::Ai::DevolucaoAIa do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Robô') }
  let(:contact) { create(:contact, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:conversation) do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
    conversa.update!(ai_assignee: bot, assignee: nil)
    conversa
  end
  let(:card) do
    pipeline, stage = vendas
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Vendas', primary_conversation: conversation,
                              inbox: inbox)
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    card
  end

  after { Current.reset }

  def como(user)
    Current.user = user
    yield
  ensure
    Current.user = nil
  end

  def atribuir(user)
    Conversations::AssignmentService.new(conversation: conversation.reload, assignee_id: user&.id).perform
  end

  def do_cliente(texto)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
  end

  def passar
    Crm::Ai::HandoffExecutor.new(card: card.reload, handoff: { intent: 'transferir' }).perform
  end

  it 'atribuição pela tela devolvida: a mesma fala não passa de novo; um pedido novo depois da devolução passa', :aggregate_failures do
    do_cliente('Quero falar com alguém')
    como(ana) { atribuir(ana) }
    como(ana) { atribuir(nil) }

    expect(described_class.em(card, conversation.reload)).to be_present
    expect(passar).to have_attributes(status: :skipped, error: 'devolvida_sem_pedido_novo')

    do_cliente('Agora quero outra coisa com uma pessoa')
    expect(passar.error).not_to eq('devolvida_sem_pedido_novo')
  end

  # O convite em si não conta (pelas_passagens o ignora): o aceite vira a passagem de atribuição, e é ela que é devolvida.
  it 'convite aceito (vira atribuição) e devolvido conta como atendido (antes o convite nunca carimbava)' do
    Crm::Passagens.registrar!(conversation: conversation, de: bot, para: ana, pedida_por: nil, motivo: 'convite')
    como(ana) { atribuir(ana) }
    como(ana) { atribuir(nil) }

    expect(passar).to have_attributes(status: :skipped, error: 'devolvida_sem_pedido_novo')
  end

  it 'convite fechado por outra passagem, sem ninguém ter atendido, não conta como devolvido' do
    Crm::Passagens.registrar!(conversation: conversation, de: bot, para: ana, pedida_por: nil, motivo: 'convite')
    Crm::Passagens.registrar!(conversation: conversation, de: bot, para: admin, pedida_por: nil, motivo: 'convite')

    expect(described_class.em(card, conversation.reload)).to be_nil
  end

  # Pega o achado do revisor: a área passou para a Ana e a Ana devolveu para a porta (outro robô).
  it 'devolvida para um robô diferente do que passou também conta como atendido' do
    area = create(:agent_bot, account: account, name: 'Área')
    Crm::Passagens.registrar!(conversation: conversation, de: area, para: ana, pedida_por: area, motivo: 'robo_pediu')
    como(ana) { atribuir(ana) }
    como(ana) { atribuir(nil) }

    expect(conversation.reload.ai_assignee).to eq(bot)
    expect(described_class.pelas_passagens(conversation)).to be_present
    expect(passar).to have_attributes(status: :skipped, error: 'devolvida_sem_pedido_novo')
  end

  it 'com uma pessoa no nome não há devolução' do
    como(ana) { atribuir(ana) }

    expect(described_class.pelas_passagens(conversation.reload)).to be_nil
  end

  describe 'o classificador lê as passagens recentes' do
    it 'conversation_state traz handoff_history cercado como dado, e nada sem passagem', :aggregate_failures do
      expect(Crm::Ai::ContextBuilder.new(card: card).perform[:conversation_state]).not_to have_key(:handoff_history)

      como(ana) { atribuir(ana) }
      como(ana) { atribuir(nil) }

      estado = Crm::Ai::ContextBuilder.new(card: card.reload).perform[:conversation_state]
      expect(estado[:handoff_history]).to start_with(Crm::Passagens::ABRE).and include('Devolvida por Ana')
      expect(estado[:returned_to_ai_at]).to be_present
    end
  end
end
