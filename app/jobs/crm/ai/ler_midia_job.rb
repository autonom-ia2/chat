# IA entende a conversa, F4: lê os anexos da mensagem nova na chegada (Crm::Ai::LeitorDeMidia), na fila high, para o
# texto estar pronto quando a IA de assunto perguntar. Sem a flag, não faz nada.
#
# O job roda no commit da mensagem, e o upload do anexo para o storage pode ainda não ter terminado. Arquivo ausente:
# tenta de novo com espera crescente (2 s, 4 s, ... 128 s; uns 4 minutos ao todo). Na última tentativa, o leitor marca
# o anexo como lido sem texto, com aviso no log.
class Crm::Ai::LerMidiaJob < ApplicationJob
  TENTATIVAS = 8

  queue_as :high
  retry_on ActiveStorage::FileNotFoundError, attempts: TENTATIVAS, wait: ->(executions) { 2**executions }

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Crm::Ai::LeitorDeMidia.new(message, ultima_tentativa: executions >= TENTATIVAS).perform
  end
end
