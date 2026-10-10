# Envio "humanizado" pelo WhatsApp API (chat#1067): "digitando…" pelo tempo que uma pessoa levaria e só
# então envia. Disparo instantâneo e sempre igual é padrão de robô para o WhatsApp.
#
# O cálculo é o Humanize v3 do google-saas (lib/services/automation/humanize), derivado do fluxo n8n
# em produção, testado com clientes reais sem ser detectado como bot — mesmos números, não mudar sem
# A/B test. Aqui a mensagem NÃO é quebrada em partes (cada mensagem do Chat2You precisa ser uma
# mensagem no WhatsApp para a conciliação com o eco da Meta); usa-se só o tempo de um "chunk" inicial.
#
# O "digitando…" é cosmético: se o motor recusar, o envio segue. WHATSAPP_HYBRID_TYPING=false desliga.
class WhatsappHybrid::Typing
  PER_CHAR_MS = (24..38)
  FIRST_CHUNK_EXTRA_MS = (700..1600)
  NEWLINE_PAUSE_MS = 180
  BULLET_PAUSE_MS = 220
  PUNCTUATION_PAUSE_MS = { '.' => 250, ',' => 90, ';' => 130, ':' => 150, '!' => 280, '?' => 320, '…' => 280 }.freeze
  MEDIA_MS = (700..1800)
  MIN_MS = 900
  MAX_MS = 15_000
  BULLET_MARKERS = ['- ', '* ', '• '].freeze

  def initialize(client, session:, chat_id:, rng: Random.new)
    @client = client
    @session = session
    @chat_id = chat_id
    @rng = rng
  end

  def simulate(message)
    return if ENV.fetch('WHATSAPP_HYBRID_TYPING', 'true').to_s.downcase == 'false'

    started = start
    Kernel.sleep(delay_ms(message) / 1000.0)
    stop if started
  end

  # O que a pessoa digitou (content), não a assinatura que o envio acrescenta.
  def delay_ms(message)
    base = message.attachments.any? ? @rng.rand(MEDIA_MS) : text_ms(message.content.to_s)
    (base + @rng.rand(FIRST_CHUNK_EXTRA_MS)).clamp(MIN_MS, MAX_MS)
  end

  private

  def text_ms(text)
    compact = text.split.join(' ')
    delay = compact.length * @rng.rand(PER_CHAR_MS)
    delay += text.count("\n") * NEWLINE_PAUSE_MS
    delay += text.lines.count { |line| bullet?(line) } * BULLET_PAUSE_MS
    delay + PUNCTUATION_PAUSE_MS.sum { |symbol, pause| text.count(symbol) * pause }
  end

  # "- item", "* item", "• item", "1. item", "2) item" — por métodos de string, sem regex.
  def bullet?(line)
    stripped = line.lstrip
    return true if BULLET_MARKERS.any? { |marker| stripped.start_with?(marker) }

    digits = stripped.chars.take_while { |char| char.between?('0', '9') }.join
    digits.present? && ['. ', ') '].any? { |marker| stripped.delete_prefix(digits).start_with?(marker) }
  end

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
