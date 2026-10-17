# `waha_location` (chat#1709, rodada 2): localização do cliente, { latitude, longitude, name, address, url, live,
# caption }. Vira o cartão de mapa da API oficial: o anexo `location` (como attach_location da Cloud) e
# `content_attributes.shared_location` { latitude, longitude, name?, address?, live? } (como RichMessages::
# ReceivedLocation). O `content` fica vazio, ou com a legenda que o cliente escreveu (`caption`, da localização ao
# vivo: "Estou chegando"), que a bolha mostra junto do mapa e a IA lê. `live: true` (localização ao vivo): só o ponto
# inicial; a bolha avisa. Coordenadas: só número finito na faixa (latitude -90 a 90, longitude -180 a 180); texto numérico vira
# número. Sem as duas válidas, nada muda (fica o texto do conector).
module Waha::RichNative::Inbound::Location
  KEY = 'shared_location'.freeze
  LIMITS = { 'latitude' => 90, 'longitude' => 180 }.freeze
  TITLE_LIMIT = 255

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    coordinates = LIMITS.to_h { |field, limit| [field, coordinate(data[field], limit)] }
    return if coordinates.value?(nil)

    attach!(message, coordinates, data)
    shared = coordinates.merge(data.slice('name', 'address').compact_blank)
    shared['live'] = true if data['live'] == true
    message.content_attributes = message.content_attributes.to_h.merge(KEY => shared)
    message.content = caption_of(data)
  end

  def caption_of(data)
    caption = data['caption']
    caption.strip.presence if caption.is_a?(String)
  end

  def attach!(message, coordinates, data)
    message.attachments.new(account_id: message.account_id, file_type: :location,
                            coordinates_lat: coordinates['latitude'], coordinates_long: coordinates['longitude'],
                            fallback_title: [data['name'], data['address']].compact_blank.join(', ').first(TITLE_LIMIT),
                            external_url: data['url'].presence)
  end

  def coordinate(value, limit)
    number = value.is_a?(String) ? Float(value, exception: false) : value
    number if [Integer, Float].any? { |klass| number.is_a?(klass) } && number.finite? && number.abs <= limit
  end
end
