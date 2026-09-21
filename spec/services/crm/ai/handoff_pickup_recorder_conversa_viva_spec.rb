require 'rails_helper'

# Issue #556. O convite R3 vai para a conversa VIVA desde a #553, mas quem registra a pega
# procurava o card pela conversa PRIMÁRIA (`Crm::Card.where(conversation_id: ...)`). Com card
# por contato, a conversa viva é quase sempre uma secundária de crm_card_conversations: não se
# achava card nenhum e o ciclo nunca fechava. O corretor sentia três coisas — badge "aguardando
# pega" preso no kanban, escalada em cima de quem já pegou, e cooldown de 6h segurando o
# próximo pedido do cliente.
RSpec.describe Crm::Ai::HandoffPickupRecorder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agente]) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:convidado_em) { 10.minutes.ago }
  let(:pego_em) { 4.minutes.ago }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

  def card_com(primaria:, tambem: [], ciclo: {})
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite' } })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: primaria, title: 'Lead com convite R3',
      metadata: metadata_de_convite(ciclo)
    )
    ([primaria] + tambem).each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  def metadata_de_convite(ciclo_extra)
    ciclo = {
      'cycle_id' => 1,
      'invited_at' => convidado_em.iso8601,
      'invited_agent_id' => agente.id
    }.merge(ciclo_extra)

    { 'ai' => { 'handoffs' => [ciclo], 'handoff' => ciclo } }
  end

  def registrar_pega(conversation)
    described_class.new(
      conversation: conversation,
      assignee_id: agente.id,
      picked_up_at_iso: pego_em.iso8601
    ).perform
  end

  def ciclo_de(card)
    card.reload.metadata.dig('ai', 'handoffs').first
  end

  it 'fecha o ciclo quando o convite foi para uma conversa secundária' do
    # Arrange — o caso real: a primeira conversa do contato foi resolvida e o convite saiu na
    # conversa nova, que entrou como secundária no card
    conversa_antiga.update!(status: :resolved)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    registrar_pega(conversa_viva)

    # Assert
    ciclo = ciclo_de(card)
    expect(ciclo['picked_up_at']).to be_present
    expect(ciclo['picked_up_by']).to eq(agente.id)
    expect(card.reload.metadata.dig('ai', 'handoff', 'picked_up_at')).to be_present
  end

  it 'derruba o badge de "aguardando pega" do kanban' do
    # Arrange — o badge sai por TERMINAL_KEYS, e picked_up_at é uma delas. Com o ciclo preso
    # aberto o corretor via "aguardando pega" para sempre, mesmo já tendo pegado a conversa.
    conversa_antiga.update!(status: :resolved)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])
    expect(Crm::Ai::HandoffInvitePayload.for_card(card)).to be_present

    # Act
    registrar_pega(conversa_viva)

    # Assert
    expect(Crm::Ai::HandoffInvitePayload.for_card(card.reload)).to be_nil
  end

  it 'grava o tempo de pega medido do convite até a atribuição' do
    # Arrange
    conversa_antiga.update!(status: :resolved)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    registrar_pega(conversa_viva)

    # Assert — sem prender o número, um carimbo qualquer passaria no teste acima
    expect(ciclo_de(card)['pickup_seconds']).to be_within(2).of((pego_em - convidado_em).round)
    expect(card.activities.where(event_type: 'ai_handoff_pickup')).to exist
  end

  it 'continua fechando o ciclo quando a conversa do convite é a própria primária' do
    # Arrange — card de conversa única, que é o caminho que já funcionava
    card = card_com(primaria: conversa_viva)

    # Act
    registrar_pega(conversa_viva)

    # Assert
    expect(ciclo_de(card)['picked_up_at']).to be_present
  end

  it 'fecha o ciclo de card legado, que não tem linha em crm_card_conversations' do
    # Arrange — card anterior ao vínculo por linha: só `conversation_id` aponta a conversa.
    # Trocar a busca por "só o que está em crm_card_conversations" deixaria esse card de fora.
    card = card_com(primaria: conversa_viva)
    card.card_conversations.destroy_all

    # Act
    registrar_pega(conversa_viva)

    # Assert
    expect(ciclo_de(card)['picked_up_at']).to be_present
  end

  it 'não carimba pega em card de outro contato que não tem esta conversa' do
    # Arrange — a busca ficou mais larga; sem isto, um `Crm::Card.all` passaria em tudo acima
    outro_contato = create(:contact, account: account)
    conversa_de_outro = create_crm_conversation(account: account, inbox: inbox, contact: outro_contato)
    card_alheio = card_com(primaria: conversa_de_outro)
    card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    registrar_pega(conversa_viva)

    # Assert
    expect(ciclo_de(card_alheio)['picked_up_at']).to be_blank
  end

  it 'não carimba pega em ciclo já fechado por escalação' do
    # Arrange — atribuição depois do ciclo fechado é ação nova, não pega do convite
    conversa_antiga.update!(status: :resolved)
    card = card_com(
      primaria: conversa_antiga, tambem: [conversa_viva],
      ciclo: { 'escalated_at' => 2.minutes.ago.iso8601 }
    )

    # Act
    registrar_pega(conversa_viva)

    # Assert
    expect(ciclo_de(card)['picked_up_at']).to be_blank
  end
end
