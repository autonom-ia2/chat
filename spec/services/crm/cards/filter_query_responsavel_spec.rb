require 'rails_helper'

# FILTRAR POR RESPONSÁVEL TEM DE ACHAR O CARD ESCALADO (issue #555).
#
# O join do filtro lia só `crm_cards.conversation_id`, a conversa primária. Desde a #553 o
# responsável entra na conversa VIVA, então "responsável: humano" perdia exatamente os cards que
# acabaram de ser passados para uma pessoa, e "responsável: bot" os trazia como se ninguém
# estivesse atendendo.
RSpec.describe Crm::Cards::FilterQuery do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:quem_atende) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [quem_atende]) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  def card_escalado
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversa_antiga, title: 'Lead escalado', metadata: {}
    )
    [conversa_antiga, conversa_viva].each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    conversa_antiga.update!(status: :resolved)
    conversa_viva.update!(assignee: quem_atende)
    card
  end

  def filtrar(kind)
    described_class.new(scope: account.crm_cards.all, params: { responsible_kind: kind }).perform.to_a
  end

  it 'card com responsável na conversa viva aparece em "humano"' do
    # Arrange
    card = card_escalado

    # Act / Assert
    expect(filtrar('agent')).to include(card)
  end

  it 'e não aparece como se ninguém estivesse atendendo' do
    # Arrange
    card = card_escalado

    # Act / Assert
    expect(filtrar('bot')).not_to include(card)
    expect(filtrar('none')).not_to include(card)
  end
end
