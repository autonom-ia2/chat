# Prepend em Whatsapp::IncomingMessageBaseService (chat#1473, P5): a localização que o cliente manda (em resposta
# ao `location_request` ou por conta própria) fica estruturada em `content_attributes.shared_location`:
#   { "latitude": -23.5505, "longitude": -46.6333, "name": "Praça da Sé", "address": "Praça da Sé, São Paulo - SP" }
# `name` e `address` só vêm quando o cliente escolhe compartilhar. O anexo de localização de antes continua igual,
# mas ele junta nome e endereço num título só (e perde o endereço quando não há nome); o robô (webhook, que leva
# `content_attributes`) e o agente leem os campos daqui. A resposta ao pedido leva também `in_reply_to`, como
# toda resposta citada. Vale para o WhatsApp oficial e o 360dialog, que passam pelo mesmo serviço.
# Coordenadas: a Meta documenta número (Float). Grava só número finito na faixa (latitude -90 a 90, longitude
# -180 a 180); texto numérico vira número (`Float(texto, exception: false)`). Sem as duas coordenadas válidas,
# não grava `shared_location`: a bolha fica com o anexo de antes.
# Só acrescenta ao final de `attach_location`; o resto do recebimento não muda. Fica de fora:
# - o eco da coexistência (`outgoing_echo`): a localização foi mandada pela empresa pelo app, não pelo cliente;
# - `location` que não é objeto: não grava nada e não interrompe o recebimento.
module RichMessages::ReceivedLocation
  KEY = 'shared_location'.freeze
  TEXT_FIELDS = %w[name address].freeze
  COORDINATE_LIMITS = { 'latitude' => 90, 'longitude' => 180 }.freeze

  private

  def attach_location
    super
    location = messages_data.first['location']
    return if outgoing_echo || !location.is_a?(Hash)

    coordinates = COORDINATE_LIMITS.to_h { |field, limit| [field, shared_coordinate(location[field], limit)] }
    return if coordinates.value?(nil)

    shared = coordinates.merge(location.to_hash.slice(*TEXT_FIELDS).compact)
    @message.content_attributes = @message.content_attributes.merge(KEY => shared)
  end

  def shared_coordinate(value, limit)
    number = value.is_a?(String) ? Float(value, exception: false) : value
    number if [Integer, Float].any? { |klass| number.is_a?(klass) } && number.finite? && number.abs <= limit
  end
end
