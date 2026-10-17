# W1 (#1601): grava a autoria da mensagem nova ou mudada. Enfileirado pelo Crm::MemoriaListener, que já conferiu a flag.
class Crm::Memoria::OrigemJob < ApplicationJob
  queue_as :low
  # Corrida com a mescla de contatos: a conversa foi lida com o contato absorvido, que o destroy! já apagou. Na nova
  # tentativa a conversa já aponta para o contato que fica.
  retry_on ActiveRecord::InvalidForeignKey, wait: 5.seconds, attempts: 3

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank? || !Crm::Memoria.ativa?(message.conversation)

    Crm::Memoria::Origem.gravar!(message)
  end
end
