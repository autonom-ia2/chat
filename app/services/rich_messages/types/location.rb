# Localização (chat#1473, P5): um ponto no mapa.
#   { "type": "location", "latitude": -23.5489, "longitude": -46.6388, "name": "Unidade Centro", "address": "Rua ..." }
# `latitude` (-90 a 90) e `longitude` (-180 a 180) são obrigatórias e chegam como número JSON (inteiro ou decimal), já calculadas por
# quem chama (o agente nativo converte endereço em coordenadas antes). `name` e `address` são opcionais, em uma
# linha só; a Meta não dá limite para eles, os 100 e 300 caracteres são nossos, para caber no cartão. Opcional em
# branco ("" ou só espaços) conta como ausente.
# Na Meta o formato não tem corpo: a mensagem vai com `content` vazio, e corpo não vazio é recusado.
class RichMessages::Types::Location
  NAME_MAX = 100
  ADDRESS_MAX = 300
  LATITUDE_RANGE = (-90..90)
  LONGITUDE_RANGE = (-180..180)
  # Quebras de linha, inclusive as do Unicode (o tab continua aceito).
  LINE_BREAKS = ["\n", "\r", "\v", "\u0085", "\u2028", "\u2029"].freeze
  # Só os números que o JSON produz. BigDecimal, Rational e Complex são recusados: o BigDecimal vira texto ao ser
  # gravado em `content_attributes` e falharia depois, no envio.
  COORDINATE_CLASSES = [Integer, Float].freeze
  # O mesmo endereço de mapa está na bolha do atendente
  # (app/javascript/dashboard/components-next/message/bubbles/RichMessage/mapLink.js): mudou um, mude o outro.
  MAP_LINK = 'https://maps.google.com/?q='.freeze

  BODY_NOT_ALLOWED = 'A localização vai sem texto: deixe a mensagem vazia e ponha nome e endereço nos campos dela.'.freeze
  LATITUDE_INVALID = 'A latitude da localização precisa ser um número entre -90 e 90.'.freeze
  LONGITUDE_INVALID = 'A longitude da localização precisa ser um número entre -180 e 180.'.freeze
  NAME_INVALID = "O nome da localização precisa ser um texto de até #{NAME_MAX} caracteres, em uma linha só.".freeze
  ADDRESS_INVALID = "O endereço da localização precisa ser um texto de até #{ADDRESS_MAX} caracteres, em uma linha só.".freeze

  def initialize(payload)
    @latitude = payload['latitude']
    @longitude = payload['longitude']
    @name = absent_if_blank(payload['name'])
    @address = absent_if_blank(payload['address'])
  end

  def error_for(body)
    return BODY_NOT_ALLOWED if body.present?
    return LATITUDE_INVALID unless coordinate?(@latitude, LATITUDE_RANGE)
    return LONGITUDE_INVALID unless coordinate?(@longitude, LONGITUDE_RANGE)
    return NAME_INVALID unless optional_line?(@name, NAME_MAX)

    ADDRESS_INVALID unless optional_line?(@address, ADDRESS_MAX)
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/location-messages
  # A Meta documenta as coordenadas como texto em graus decimais.
  def whatsapp_cloud_payload(_body)
    {
      type: 'location',
      location: { latitude: decimal(@latitude), longitude: decimal(@longitude), name: @name, address: @address }.compact
    }
  end

  # Nome, endereço e um link de mapa montado com as coordenadas, um por linha.
  def fallback_text(_body)
    [@name, @address, "#{MAP_LINK}#{decimal(@latitude)},#{decimal(@longitude)}"].compact.join("\n")
  end

  private

  def coordinate?(value, range)
    COORDINATE_CLASSES.any? { |klass| value.is_a?(klass) } && value.finite? && range.cover?(value)
  end

  def absent_if_blank(value)
    value unless value.is_a?(String) && value.blank?
  end

  def optional_line?(text, max)
    text.nil? || (text.is_a?(String) && text.length <= max && LINE_BREAKS.none? { |line_break| text.include?(line_break) })
  end

  # Notação decimal comum, sem perder casas, sempre com ao menos uma casa e sem notação científica: 90 → "90.0",
  # 1.0e-07 → "0.0000001". As bolhas (RichMessage/mapLink.js, `decimalOf`) escrevem igual, para o link sair o mesmo.
  def decimal(value)
    BigDecimal(value.to_s).to_s('F')
  end
end
