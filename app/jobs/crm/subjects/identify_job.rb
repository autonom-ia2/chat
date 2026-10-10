# Multifunil 5/11 (#1145): pergunta o assunto da mensagem recebida, depois da espera (Crm::Subjects::DEBOUNCE). Se o
# cliente mandou outra mensagem nesse meio-tempo, quem pergunta é o job dela: uma rajada vira uma pergunta só.
class Crm::Subjects::IdentifyJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, message_id)
    return unless Crm::Config.enabled?

    conversation = Conversation.find_by(id: conversation_id)
    message = conversation&.messages&.find_by(id: message_id)
    return if message.blank?
    return if conversation.messages.incoming.exists?(id: (message.id + 1)..)

    Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
  end
end
