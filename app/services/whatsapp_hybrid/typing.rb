# Envio "humanizado" pelo WhatsApp API (chat#1067). Imita uma pessoa respondendo:
# 1. lê a última mensagem do cliente (pausa proporcional ao tamanho dela, sem "digitando…");
# 2. digita a resposta a uma velocidade de pessoa, sorteada a cada mensagem (nunca o mesmo tempo);
# 3. envia. Disparo instantâneo e sempre igual é padrão de robô para o WhatsApp.
# O "digitando…" é cosmético: se o motor recusar, o envio segue. WHATSAPP_HYBRID_TYPING=false desliga.
class WhatsappHybrid::Typing
  READING_CHARS_PER_SECOND = 30.0
  READING_RANGE = (0.5..2.5)
  TYPING_CHARS_PER_SECOND = (4.5..6.5)
  TYPING_RANGE = (1.0..9.0)
  MEDIA_RANGE = (1.5..2.5)

  def initialize(client, session:, chat_id:, rng: Random.new)
    @client = client
    @session = session
    @chat_id = chat_id
    @rng = rng
  end

  def simulate(message)
    return if ENV.fetch('WHATSAPP_HYBRID_TYPING', 'true').to_s.downcase == 'false'

    Kernel.sleep(reading_for(message))
    started = start
    Kernel.sleep(typing_for(message))
    stop if started
  end

  def reading_for(message)
    last_incoming = message.conversation.messages.incoming.where(created_at: ...message.created_at).last
    (last_incoming&.content.to_s.length / READING_CHARS_PER_SECOND).clamp(READING_RANGE.begin, READING_RANGE.end)
  end

  def typing_for(message)
    return @rng.rand(MEDIA_RANGE) if message.attachments.any?

    # O que a pessoa digitou (content), não a assinatura que o envio acrescenta.
    speed = @rng.rand(TYPING_CHARS_PER_SECOND)
    (message.content.to_s.length / speed).clamp(TYPING_RANGE.begin, TYPING_RANGE.end)
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
