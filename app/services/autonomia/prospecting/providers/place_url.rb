# URL de um lugar do Google que cabe na coluna do lead (#723). O ApplicationRecord limita coluna string a 255, e um único
# site com rastreio longo derrubava a busca inteira, com o Google já pago (busca 20 da conta 1, 25/09). Na ordem: a URL
# como veio, sem os parâmetros de rastreio (o cid do Maps e o resto da query ficam), sem query e fragmento, e por fim
# vazio. O lead entra sempre.
module Autonomia::Prospecting::Providers::PlaceUrl
  COLUMN_LIMIT = 255
  TRACKING_PREFIXES = %w[utm_].freeze
  TRACKING_PARAMS = %w[gclid gbraid wbraid fbclid msclkid mc_cid mc_eid _ga igshid].freeze

  module_function

  def fit(value)
    url = value.to_s.strip
    return url.presence if url.length <= COLUMN_LIMIT

    uri = URI.parse(url)
    [without_tracking(uri), without_query(uri)].find { |candidate| candidate.length <= COLUMN_LIMIT }
  rescue URI::InvalidURIError
    nil
  end

  def without_tracking(uri)
    kept = URI.decode_www_form(uri.query.to_s).reject { |key, _value| tracking?(key) }
    rebuild(uri, kept.empty? ? nil : URI.encode_www_form(kept))
  rescue ArgumentError
    without_query(uri)
  end

  def without_query(uri)
    rebuild(uri, nil)
  end

  def rebuild(uri, query)
    uri.dup.tap do |copy|
      copy.query = query
      copy.fragment = nil
    end.to_s
  end

  def tracking?(key)
    name = key.to_s.downcase
    TRACKING_PREFIXES.any? { |prefix| name.start_with?(prefix) } || TRACKING_PARAMS.include?(name)
  end
end
