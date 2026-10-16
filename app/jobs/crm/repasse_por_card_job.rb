# Decisão "a" (#1606): o card mudou de funil. Um job por card avalia, em lotes, as conversas dele em andamento com pessoa
# no nome (a principal e as vinculadas). Ver Crm::Repasse.
class Crm::RepassePorCardJob < ApplicationJob
  queue_as :default

  LOTE = 100

  def perform(card_id)
    return unless Crm::Config.enabled?

    card = Crm::Card.find_by(id: card_id)
    return if card.nil?

    conversas(card).find_each(batch_size: LOTE) { |conversation| Crm::Repasse.sugerir!(conversation) }
  end

  private

  def conversas(card)
    vinculadas = Crm::CardConversation.where(account_id: card.account_id, card_id: card.id).select(:conversation_id)
    Conversation.where(account_id: card.account_id, status: %i[open pending]).where.not(assignee_id: nil)
                .where(id: vinculadas).or(
                  Conversation.where(account_id: card.account_id, status: %i[open pending], id: card.conversation_id)
                              .where.not(assignee_id: nil)
                )
  end
end
