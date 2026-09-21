require 'rails_helper'

# Issue #553, segunda metade. Quando ninguém está online, o executor guarda um marcador de espera
# no card e este job drena mais tarde. Ele lia `card.primary_conversation`: com a primária antiga
# carregando um responsável de semanas atrás, o job concluía "humano já assumiu", APAGAVA o
# marcador e nada mais tentava. O cliente que pediu atendimento de madrugada nunca era atendido.
RSpec.describe Crm::Ai::HandoffDrainJob do
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

  # O card como o executor o deixa quando segura a escalada por falta de gente online.
  def card_em_espera
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversa_antiga, title: 'Lead handoff',
      metadata: { 'ai' => { 'handoff_hold' => { 'held_at' => Time.current.iso8601,
                                                'handoff' => { 'intent' => 'transferir', 'reason' => 'cliente pediu humano' } } } }
    )
    [conversa_antiga, conversa_viva].each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  it 'atende a conversa viva mesmo com responsável antigo na primária' do
    # Arrange — exatamente o estado da conta 16: primária resolvida e com dono, cliente esperando
    conversa_antiga.update!(status: :resolved, assignee: atendente_antigo)
    card = card_em_espera

    # Act
    described_class.perform_now

    # Assert
    expect(conversa_viva.reload.assignee_id).to eq(agent.id)
    expect(card.reload.metadata.dig('ai', 'handoff_hold')).to be_nil
  end

  it 'não apaga a espera por causa de um responsável que está na conversa errada' do
    # Arrange — ninguém online: o marcador tem de sobreviver para o próximo tick
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
    conversa_antiga.update!(status: :resolved, assignee: atendente_antigo)
    card = card_em_espera

    # Act
    described_class.perform_now

    # Assert
    expect(card.reload.metadata.dig('ai', 'handoff_hold', 'held_at')).to be_present
    expect(conversa_viva.reload.assignee_id).to be_nil
  end

  it 'humano que assumiu a conversa viva encerra a espera' do
    # Arrange — aqui o "já assumiu" é verdade, e o marcador deve mesmo sair
    conversa_viva.update!(assignee: atendente_antigo)
    card = card_em_espera

    # Act
    described_class.perform_now

    # Assert
    expect(card.reload.metadata.dig('ai', 'handoff_hold')).to be_nil
    expect(conversa_viva.reload.assignee_id).to eq(atendente_antigo.id)
  end
end
