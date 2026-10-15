# Entrega a conversa ao agente de IA responsável pelo assunto em atendimento (#1447). Ver Crm::Ai::ResponsibleAgentSync.
class Crm::Ai::ResponsibleAgentSyncJob < ApplicationJob
  # A troca de agente decide quem responde ao cliente agora: a mesma fila da resposta do agente (ReplyJob).
  queue_as :medium

  def perform(conversation_id, motivo, card_id = nil)
    return unless Crm::Config.enabled?

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless Crm::Ai::ResponsibleAgentSync::MOTIVOS.include?(motivo.to_s)

    Crm::Ai::ResponsibleAgentSync.new(conversation: conversation, motivo: motivo, card_id: card_id).perform
  end
end
