# Memória das IAs (#1601): a mensagem apagada ou editada mexe nos fatos que ela provava (Crm::Memoria::Recalcular).
class Crm::Memoria::MensagemJob < ApplicationJob
  queue_as :low
  EVENTOS = %w[apagada editada].freeze

  def perform(message_id, evento)
    message = Message.find_by(id: message_id)
    return if message.nil? || EVENTOS.exclude?(evento) || !Crm::Memoria.ativa?(message.conversation)

    evento == 'apagada' ? Crm::Memoria::Recalcular.mensagem_apagada!(message) : Crm::Memoria::Recalcular.mensagem_editada!(message)
  end
end
