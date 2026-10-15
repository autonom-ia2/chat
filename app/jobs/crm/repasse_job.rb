# Decisão "a" (#1606): o assunto em atendimento mudou (foco em outro card, ou o card mudou de funil). Se uma pessoa está
# com a conversa e não cuida do funil novo, grava a sugestão de passar para a equipe dele. Ver Crm::Repasse.
class Crm::RepasseJob < ApplicationJob
  queue_as :default

  # Só conversa com pessoa no nome, e só quando há o que avaliar: o resto da decisão é do Crm::Repasse, sob a trava.
  def self.agendar(conversation_ids)
    Conversation.where(id: conversation_ids, status: %i[open pending]).where.not(assignee_id: nil).pluck(:id).each do |id|
      perform_later(id)
    end
  end

  def perform(conversation_id)
    return unless Crm::Config.enabled?

    conversation = Conversation.find_by(id: conversation_id)
    Crm::Repasse.sugerir!(conversation) if conversation
  end
end
