# Tentativas de recuperar a mensagem "não suportada" pelo aparelho conectado (chat#1489). Recebe só ids.
# Esperas entre as tentativas: WhatsappHybrid::UnsupportedRecovery::RETRY_DELAYS (5 s até 10 min) e, depois, de 10 em 10
# minutos, até 30 minutos do recebimento. Passou disso sem recuperar: `hybrid_recovery: failed` e a bolha manda olhar
# no celular. Erro inesperado numa tentativa não para a fila: vai ao log (só a classe) e tenta de novo.
class WhatsappHybrid::RecoverUnsupportedJob < ApplicationJob
  queue_as :default

  def perform(message_id, attempt = 0)
    message = Message.find_by(id: message_id)
    return if message.nil? || !WhatsappHybrid::UnsupportedRecovery.pending?(message)

    recovery = WhatsappHybrid::UnsupportedRecovery.new(message)
    return if attempt_once(recovery, message) == :done

    schedule_next(recovery, message, attempt)
  end

  private

  def attempt_once(recovery, message)
    recovery.attempt!
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_hybrid] recovery attempt error=#{e.class} message=#{message.id}")
    :retry
  end

  def schedule_next(recovery, message, attempt)
    remaining = message.created_at + WhatsappHybrid::UnsupportedRecovery::DEADLINE - Time.current
    return recovery.fail!('timeout') if remaining <= 0

    delays = WhatsappHybrid::UnsupportedRecovery::RETRY_DELAYS
    wait = [delays[attempt + 1] || delays.last, remaining].min
    self.class.set(wait: wait).perform_later(message.id, attempt + 1)
  end
end
