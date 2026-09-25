# Dado de fora (Google, site raspado) que cabe na coluna string do lead (#723). O ApplicationRecord limita coluna string a
# 255 (validates_column_content_length), e um único valor maior derrubava a busca inteira, com o Google já pago (busca
# 20 da conta 1, 25/09), ou o enriquecimento do lead.
#
# url: como veio; sem os parâmetros de rastreio (o resto da query fica, inclusive o cid do Maps); sem query e fragmento,
# quando a query não identifica a página (drop_query: true, o site); e por fim vazio. Vazio é melhor que um link que abre
# outra página, como o Maps genérico sem o cid.
# text: nome, endereço e afins cortados no limite. O lead entra sempre.
module Autonomia::Prospecting::ColumnFit
  LIMIT = 255
  TRACKING_PREFIXES = %w[utm_].freeze
  TRACKING_PARAMS = %w[gclid gbraid wbraid fbclid msclkid mc_cid mc_eid _ga igshid].freeze

  module_function

  def url(value, drop_query: true)
    url = value.to_s.strip
    return url.presence if url.length <= LIMIT

    uri = URI.parse(url)
    candidates = [without_tracking(uri)]
    candidates << without_query(uri) if drop_query
    candidates.find { |candidate| candidate.length <= LIMIT }
  rescue URI::InvalidURIError
    nil
  end

  def text(value)
    value&.to_s&.first(LIMIT)
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
