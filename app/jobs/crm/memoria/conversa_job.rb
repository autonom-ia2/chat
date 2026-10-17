# Memória das IAs (#1601): o que muda na tarefa de retomar por um evento da conversa, fora do caminho de quem mudou.
#   'dono'      -> a troca de responsável (ASSIGNEE_CHANGED): a tarefa acompanha quem está com a conversa.
#   'resolvida' -> a conversa resolvida com a tarefa aberta fica marcada "confirmar".
#   'segurada'  -> a Entrega segurou a conversa (ninguém pode receber): nasce a tarefa, uma por conversa.
class Crm::Memoria::ConversaJob < ApplicationJob
  queue_as :low
  EVENTOS = %w[dono resolvida segurada].freeze

  def perform(conversation_id, evento)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil? || EVENTOS.exclude?(evento) || !Crm::Memoria.ativa?(conversation)

    compromissos = Crm::Memoria::Compromissos
    case evento
    when 'dono' then compromissos.acompanhar_dono!(conversation)
    when 'resolvida' then compromissos.conversa_resolvida!(conversation)
    else segurada(conversation)
    end
  end

  private

  def segurada(conversation)
    marca = Crm::Entrega::Marca.dados(conversation)
    return unless marca && marca['modo'] == Crm::Entrega::Marca::SEGURANDO

    Crm::Memoria::Compromissos.abrir_retomada!(conversation: conversation, origem: 'segurada')
  end
end
