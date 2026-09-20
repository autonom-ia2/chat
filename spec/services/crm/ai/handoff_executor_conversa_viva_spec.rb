require 'rails_helper'

# Issue #553. O executor agia em `card.primary_conversation`, que é a PRIMEIRA conversa do
# contato. Da segunda em diante, o responsável ia para uma conversa antiga e a conversa em que
# o cliente acabou de escrever ficava aberta e sem ninguém — e quando a primária já tinha
# responsável, a guarda `already_assigned` dava o handoff por feito sem ter feito nada.
# Em produção (conta 16), 4 das 5 escaladas de 30 dias terminaram sem responsável.
RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:atendente_antigo) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, atendente_antigo]) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id => 'online' })
  end

  def card_com(primaria:, tambem: [])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: primaria, title: 'Lead handoff', metadata: { 'ai' => {} }
    )
    ([primaria] + tambem).each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  def escalar(card)
    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'cliente pediu humano' }).perform
  end

  it 'atribui a conversa em que o cliente está falando, e não a primária do card' do
    # Arrange — a antiga foi resolvida, como acontece sempre que o atendimento anterior fechou
    conversa_antiga.update!(status: :resolved)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    resultado = escalar(card)

    # Assert
    expect(resultado.status).to eq(:handed_off)
    expect(conversa_viva.reload.assignee_id).to eq(agent.id)
    expect(conversa_antiga.reload.assignee_id).to be_nil
  end

  it 'não se dá por satisfeito porque a conversa antiga já tinha responsável' do
    # Arrange — o caso da conta 16: primária com responsável de semanas atrás, cliente esperando
    # na conversa nova. A guarda `already_assigned` olhava a conversa errada e abortava o handoff.
    conversa_antiga.update!(status: :resolved, assignee: atendente_antigo)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    resultado = escalar(card)

    # Assert
    expect(resultado.status).to eq(:handed_off)
    expect(conversa_viva.reload.assignee_id).to eq(agent.id)
    expect(conversa_antiga.reload.assignee_id).to eq(atendente_antigo.id)
  end

  it 'com uma conversa só, continua sendo ela' do
    # Arrange
    card = card_com(primaria: conversa_viva)

    # Act
    resultado = escalar(card)

    # Assert
    expect(resultado.status).to eq(:handed_off)
    expect(conversa_viva.reload.assignee_id).to eq(agent.id)
  end

  it 'conversa viva já atribuída não é reatribuída' do
    # Arrange — quem já está com uma pessoa não volta para a fila
    conversa_antiga.update!(status: :resolved)
    conversa_viva.update!(assignee: atendente_antigo)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    resultado = escalar(card)

    # Assert
    expect(resultado.status).to eq(:skipped)
    expect(conversa_viva.reload.assignee_id).to eq(atendente_antigo.id)
  end
end
