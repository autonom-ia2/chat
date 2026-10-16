# Convite de evento (chat#1709, rodada 2): o nome no corpo (`content`) e a data, para o cliente responder "Vou / Não vou".
#   { "type": "event", "start_at": "2026-10-20T14:00:00-03:00", "end_at": "2026-10-20T15:00:00-03:00",
#     "location_name": "Av. Paulista, 1000", "description": "Vistoria do carro" }
# `end_at`, `location_name` e `description` são opcionais. As datas são ISO 8601 COM o fuso (offset), no futuro, e o
# fim depois do início. Só existe com a flag `whatsapp_rich_native` na conta (Waha::RichNative::PollGate; sem ela o tipo
# é desconhecido, como na main). Nativo só pelo motor WAHA (`sendEvent`, plano B do Híbrido e caixa WAHA comum com o
# conector c2y-rich-3): a Cloud API não tem convite de evento, então lá sai como texto e a bolha mostra "Enviado como
# texto". O motor não cancela evento: cancelar não é oferecido (mande um texto).
# A data no texto sai no fuso que veio no `start_at` (quem manda usa o fuso da conta), sem nome de fuso.
class RichMessages::Types::Event
  BODY_MAX = 255
  LOCATION_MAX = 255
  DESCRIPTION_MAX = 2048
  LINE_BREAKS = RichMessages::Types::Options::LINE_BREAKS
  DATE_FORMAT = '%d/%m/%Y %H:%M'.freeze
  TIME_FORMAT = '%H:%M'.freeze

  BODY_INVALID = "O convite de evento precisa do nome do evento no texto da mensagem, com até #{BODY_MAX} caracteres.".freeze
  START_INVALID = 'O convite de evento precisa de start_at: data e hora futuras em ISO 8601 com o fuso (ex.: 2026-10-20T14:00:00-03:00).'.freeze
  END_INVALID = 'O end_at do convite de evento precisa ser data e hora em ISO 8601 com o fuso, depois do início.'.freeze
  LOCATION_INVALID = "O local do convite de evento precisa ser um texto de até #{LOCATION_MAX} caracteres, em uma linha só.".freeze
  DESCRIPTION_INVALID = "A descrição do convite de evento precisa ser um texto de até #{DESCRIPTION_MAX} caracteres.".freeze

  def initialize(payload)
    @start_text = payload['start_at']
    @end_text = payload['end_at']
    @location_name = payload['location_name']
    @description = payload['description']
  end

  def start_at
    @start_at = parse(@start_text) unless defined?(@start_at)
    @start_at
  end

  def end_at
    @end_at = parse(@end_text) unless defined?(@end_at)
    @end_at
  end

  def error_for(body)
    return BODY_INVALID unless line?(body, BODY_MAX)

    date_error || text_error
  end

  # A Cloud API não tem convite de evento: o nome e os dados, como texto.
  def whatsapp_cloud_payload(body)
    { type: 'text', text: { body: "📅 #{body}\n#{fallback_text(body)}", preview_url: false } }
  end

  # Data e hora (e o fim), o local e a descrição, uma linha cada. Sem palavras: serve a qualquer idioma.
  def fallback_text(_body)
    when_line = "🕐 #{start_at.strftime(DATE_FORMAT)}"
    when_line += "–#{end_at.strftime(end_at.to_date == start_at.to_date ? TIME_FORMAT : DATE_FORMAT)}" if end_at
    [when_line, (@location_name.presence && "📍 #{@location_name}"), @description.presence].compact.join("\n")
  end

  private

  def date_error
    return START_INVALID if start_at.nil? || start_at <= Time.current

    END_INVALID unless @end_text.nil? || (end_at && end_at > start_at)
  end

  def text_error
    return LOCATION_INVALID unless @location_name.nil? || line?(@location_name, LOCATION_MAX)

    DESCRIPTION_INVALID unless optional_text?(@description, DESCRIPTION_MAX)
  end

  # A data com o fuso que veio (sem ele, nil: o horário seria ambíguo).
  def parse(text)
    return unless text.is_a?(String) && Date._iso8601(text)[:offset]

    Time.iso8601(text)
  rescue ArgumentError
    nil
  end

  def optional_text?(text, max)
    text.nil? || (text.is_a?(String) && text.strip.present? && text.length <= max)
  end

  # Texto preenchido, até `max`, numa linha só.
  def line?(text, max)
    optional_text?(text, max) && !text.nil? && LINE_BREAKS.none? { |line_break| text.include?(line_break) }
  end
end
