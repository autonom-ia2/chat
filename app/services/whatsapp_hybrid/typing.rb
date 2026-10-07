# Envio "humanizado" pelo WhatsApp API (chat#1067): mostra "digitando…" e espera um tempo
# proporcional ao texto antes de enviar. Disparo instantâneo, sempre igual, é padrão de robô para o
# WhatsApp. O "digitando…" é cosmético: se o motor recusar, o envio segue normalmente.
# Desligável por ENV WHATSAPP_HYBRID_TYPING=false.
class WhatsappHybrid::Typing
  SECONDS_PER_CHAR = 0.04
  MIN_SECONDS = 1.0
  MAX_SECONDS = 4.0
  MEDIA_SECONDS = 1.5

  def initialize(client, session:, chat_id:)
    @client = client
    @session = session
    @chat_id = chat_id
  end

  def simulate(message)
    return if ENV.fetch('WHATSAPP_HYBRID_TYPING', 'true').to_s.downcase == 'false'

    started = start
    Kernel.sleep(duration_for(message))
    stop if started
  end

  def duration_for(message)
    return MEDIA_SECONDS if message.attachments.any?

    (message.outgoing_content.to_s.length * SECONDS_PER_CHAR).clamp(MIN_SECONDS, MAX_SECONDS)
  end

  private

  def start
    @client.start_typing(session: @session, chat_id: @chat_id)
    true
  rescue Waha::Client::Error => e
    Rails.logger.info("[whatsapp_hybrid] typing indicator skipped: #{e.class}")
    false
  end

  def stop
    @client.stop_typing(session: @session, chat_id: @chat_id)
  rescue Waha::Client::Error => e
    Rails.logger.info("[whatsapp_hybrid] typing stop skipped: #{e.class}")
  end
end
