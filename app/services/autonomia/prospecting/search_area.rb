# Área desenhada da busca (#678, E2 frente B): círculo, retângulo e polígono, além do raio e da área visível que já
# existiam. Aqui mora a geometria: normalizar o que vem da tela, montar a posição do pedido ao Google e dizer se um
# lugar está dentro do polígono.
#
# O Google só aceita círculo como viés (locationBias) e só aceita retângulo como restrição (locationRestriction).
# Por isso o círculo desenhado vai como viés, e retângulo e polígono vão como restrição: quem desenhou quer o que está
# dentro. O polígono pede o retângulo que o contém e o recorte ponto no polígono vem depois, na resposta.
module Autonomia::Prospecting::SearchArea
  DRAWN_TYPES = %w[circle rectangle polygon].freeze
  TYPES = (%w[radius viewport] + DRAWN_TYPES).freeze
  # Teto do Google para o raio do círculo de locationBias.
  MAX_CIRCLE_RADIUS = 50_000
  # Pontos demais incham a busca gravada e a chave do cache sem ganho de precisão para quem desenha à mão.
  MAX_POLYGON_POINTS = 100
  MIN_POLYGON_POINTS = 3
  COORDINATE_DIGITS = 6

  module_function

  def drawn?(area_type)
    DRAWN_TYPES.include?(area_type.to_s)
  end

  # Configuração gravada da área desenhada, ou nil quando o desenho não serve (falta centro, limite ou ponto).
  def normalize(area_type, raw_config, radius:)
    config = raw_config.to_h.deep_stringify_keys
    case area_type.to_s
    when 'circle' then normalize_circle(config, radius)
    when 'rectangle' then normalize_rectangle(config)
    when 'polygon' then normalize_polygon(config)
    end
  end

  # Só o polígono recorta. Lugar sem coordenada não prova que está dentro e sai.
  def contains?(area_type, config, latitude, longitude)
    return true unless area_type.to_s == 'polygon'

    lat = coordinate(latitude)
    lng = coordinate(longitude)
    return false if lat.nil? || lng.nil?

    point_in_polygon?(lat, lng, Array(config.to_h['path']))
  end

  # Pedaço de posição do corpo do searchText: { locationBias: ... }, { locationRestriction: ... } ou {}.
  def google_location(area_type, config, radius:)
    config = config.to_h.deep_stringify_keys
    case area_type.to_s
    when 'rectangle', 'polygon'
      rectangle = google_rectangle(config['bounds'])
      rectangle ? { locationRestriction: { rectangle: rectangle } } : {}
    when 'viewport'
      rectangle = google_rectangle(config['bounds'])
      rectangle ? { locationBias: { rectangle: rectangle } } : circle_bias(config, radius)
    else
      circle_bias(config, area_type.to_s == 'circle' ? config['radius'] || radius : radius)
    end
  end

  def normalize_circle(config, radius)
    center = normalize_point(config['center'])
    return if center.nil? || radius.to_i <= 0

    { 'center' => center, 'radius' => radius.to_i }
  end

  def normalize_rectangle(config)
    bounds = normalize_bounds(config['bounds'])
    return if bounds.nil?

    { 'bounds' => bounds, 'center' => center_of(bounds) }
  end

  def normalize_polygon(config)
    raw_path = config['path']
    return unless raw_path.is_a?(Array) && raw_path.size.between?(MIN_POLYGON_POINTS, MAX_POLYGON_POINTS)

    path = raw_path.filter_map { |point| normalize_point(point) }
    return if path.size < MIN_POLYGON_POINTS || path.uniq.size < MIN_POLYGON_POINTS

    bounds = bounds_of(path)
    { 'path' => path, 'bounds' => bounds, 'center' => center_of(bounds) }
  end

  def normalize_point(value)
    hash = value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : {}
    lat = coordinate(hash['lat'] || hash['latitude'])
    lng = coordinate(hash['lng'] || hash['longitude'])
    return unless valid_point?(lat, lng)

    { 'lat' => lat, 'lng' => lng }
  end

  def valid_point?(lat, lng)
    !lat.nil? && !lng.nil? && lat.abs <= 90 && lng.abs <= 180
  end

  def normalize_bounds(value)
    hash = value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : {}
    north, south, east, west = hash.values_at('north', 'south', 'east', 'west').map { |item| coordinate(item) }
    return if [north, south, east, west].any?(&:nil?)

    { 'north' => [north, south].max, 'south' => [north, south].min, 'east' => east, 'west' => west }
  end

  def bounds_of(path)
    lats = path.pluck('lat')
    lngs = path.pluck('lng')
    { 'north' => lats.max, 'south' => lats.min, 'east' => lngs.max, 'west' => lngs.min }
  end

  def center_of(bounds)
    {
      'lat' => ((bounds['north'] + bounds['south']) / 2.0).round(COORDINATE_DIGITS),
      'lng' => ((bounds['east'] + bounds['west']) / 2.0).round(COORDINATE_DIGITS)
    }
  end

  # Ray casting com longitude no eixo x e latitude no eixo y, como no Orth (area-utils.ts pointInPolygon).
  def point_in_polygon?(lat, lng, path)
    inside = false
    path.each_with_index do |point, index|
      previous = path[index - 1]
      yi = point['lat'].to_f
      xi = point['lng'].to_f
      yj = previous['lat'].to_f
      xj = previous['lng'].to_f
      crosses = (yi > lat) != (yj > lat) && lng < ((xj - xi) * (lat - yi) / (yj - yi)) + xi
      inside = !inside if crosses
    end
    inside
  end

  def google_rectangle(bounds)
    return if bounds.blank?

    {
      low: { latitude: bounds['south'].to_f, longitude: bounds['west'].to_f },
      high: { latitude: bounds['north'].to_f, longitude: bounds['east'].to_f }
    }
  end

  def circle_bias(config, radius)
    center = config['center']
    return {} if center.blank?

    {
      locationBias: {
        circle: {
          center: { latitude: center['lat'].to_f, longitude: center['lng'].to_f },
          radius: [radius.to_i, MAX_CIRCLE_RADIUS].min
        }
      }
    }
  end

  def coordinate(value)
    return if value.blank?

    Float(value).round(COORDINATE_DIGITS)
  rescue ArgumentError, TypeError
    nil
  end
end
