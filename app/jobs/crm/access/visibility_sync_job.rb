# Fora da transação do card (#1148, parte C): ver Crm::Access::VisibilitySync.
class Crm::Access::VisibilitySyncJob < ApplicationJob
  queue_as :low

  def perform(conversation_ids)
    Crm::Access::CountInvalidation.sync_started!(conversation_ids)
    Conversation.where(id: conversation_ids).find_each { |conversation| Crm::Access::VisibilitySync.perform(conversation) }
  end
end
