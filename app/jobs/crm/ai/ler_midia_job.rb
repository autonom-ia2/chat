# IA entende a conversa, F4: lê os anexos da mensagem nova na chegada (Crm::Ai::LeitorDeMidia), na fila high, para o
# texto estar pronto quando a IA de assunto perguntar. Sem a flag, não faz nada.
class Crm::Ai::LerMidiaJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Crm::Ai::LeitorDeMidia.new(message).perform
  end
end
