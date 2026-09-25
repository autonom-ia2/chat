require 'json'
require 'uri'

class Autonomia::Prospecting::Providers::GooglePlacesProvider
  ENDPOINT = 'https://places.googleapis.com/v1/places:searchText'.freeze
  FIELD_MASK = [
    'places.id',
    'places.displayName',
    'places.formattedAddress',
    'places.addressComponents',
    'places.googleMapsUri',
    'places.location',
    'places.rating',
    'places.userRatingCount',
    'places.types',
    'places.nationalPhoneNumber',
    'places.internationalPhoneNumber',
    'places.websiteUri',
    'places.reviews',
    'places.photos',
    'places.currentOpeningHours.openNow',
    'places.currentOpeningHours.weekdayDescriptions',
    'places.regularOpeningHours.weekdayDescriptions',
    'nextPageToken'
  ].join(',').freeze
  # Teto do Google por página e por busca: 3 páginas de 20, encadeadas pelo nextPageToken (#678).
  MAX_RESULTS_PER_REQUEST = 20
  MAX_PAGES = 3
  MAX_RESULTS = MAX_RESULTS_PER_REQUEST * MAX_PAGES
  # Tipos de addressComponents, na ordem de preferência. Cidade sem locality é o município (administrative_area_level_2),
  # como no Orth (lib/services/search/search-filters.ts).
  NEIGHBORHOOD_TYPES = %w[sublocality_level_1 sublocality neighborhood].freeze
  CITY_TYPES = %w[locality administrative_area_level_2].freeze
  # Colunas string do lead que recebem texto livre do Google (#723).
  TEXT_COLUMNS = %i[name address category neighborhood city].freeze

  attr_reader :api_units

  def initialize(query:, location:, radius:, limit:, api_key:, area_type: 'radius', area_config: {}, account_id: nil,
                 country: Autonomia::Prospecting::SearchCountry::DEFAULT)
    @query = query.to_s.strip
    @location = location.to_s.strip
    @radius = radius.to_i
    @area_type = area_type.to_s
    @area_config = area_config.to_h.deep_stringify_keys
    @limit = limit.to_i
    @api_key = api_key.to_s
    @account_id = account_id
    @country = Autonomia::Prospecting::SearchCountry.normalize(country) || Autonomia::Prospecting::SearchCountry::DEFAULT
    @api_units = 0
    @partial = false
  end

  # true quando uma página depois da primeira falhou e a busca ficou com o que as anteriores trouxeram (#678).
  def partial?
    @partial
  end

  # Lê páginas de 20 até completar o pedido, até max_results posições ou até o Google parar de mandar token (#678).
  # O bloco, quando vem, diz se o lugar na posição rank passa nos filtros de quem chama: só os aceitos contam para
  # o pedido. Devolve todos os lugares lidos, na ordem do Google (posição = índice + 1); filtrar e cortar no pedido é
  # de quem chama. Cada página é uma unidade de api_units.
  def search(max_results: MAX_RESULTS)
    @api_units = 0
    @partial = false
    max_results = max_results.to_i.clamp(0, MAX_RESULTS)
    results = []
    accepted = 0
    page_token = nil

    loop do
      page = fetch_page_or_stop(page_token)
      break if page.nil?

      Array(page['places']).first(max_results - results.size).each do |place|
        results << lead_for(place)
        accepted += 1 if !block_given? || yield(results.last, results.size)
      end
      page_token = page['nextPageToken'].presence
      break unless next_page?(page_token, accepted, results.size, max_results)
    end

    results
  end

  private

  # A primeira página falha como sempre. Uma página seguinte que falha não joga fora os lugares já recebidos nem as
  # chamadas já pagas: a busca termina com o que tem e fica marcada como parcial.
  def fetch_page_or_stop(page_token)
    fetch_page(page_token)
  rescue Autonomia::Prospecting::SearchRunner::ProviderError => e
    raise if page_token.nil?

    Rails.logger.warn("[Prospecting::GooglePlaces] search account_id=#{@account_id} página seguinte falhou, busca parcial: #{e.message}")
    @partial = true
    nil
  end

  def next_page?(page_token, accepted, collected, max_results)
    page_token.present? && accepted < @limit && collected < max_results && @api_units < MAX_PAGES
  end

  def fetch_page(page_token)
    response = HTTParty.post(ENDPOINT, body: request_body(page_token).to_json, headers: headers, timeout: 10)
    @api_units += 1
    raise provider_error(response) unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError, *Autonomia::Prospecting::GoogleErrorMessage::NETWORK_ERRORS => e
    raise Autonomia::Prospecting::SearchRunner::ProviderError,
          Autonomia::Prospecting::GoogleErrorMessage.for_exception(e, context: 'search', account_id: @account_id)
  end

  # Página sempre cheia: o filtro de quem chama descarta parte dela, e pedir só o que falta cortaria lugares que
  # passariam (#678). As páginas seguintes repetem o pedido e acrescentam o token.
  def request_body(page_token)
    {
      textQuery: [@query, @location].compact_blank.join(' '),
      pageSize: MAX_RESULTS_PER_REQUEST,
      languageCode: Autonomia::Prospecting::SearchCountry.language_code(@country),
      regionCode: @country
    }.merge(location_bias_payload).merge(page_token ? { pageToken: page_token } : {})
  end

  # Viés ou restrição conforme o tipo de área (#678): a geometria mora em SearchArea.
  def location_bias_payload
    Autonomia::Prospecting::SearchArea.google_location(@area_type, @area_config, radius: @radius)
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => FIELD_MASK
    }
  end

  def provider_error(response)
    Autonomia::Prospecting::SearchRunner::ProviderError.new(
      Autonomia::Prospecting::GoogleErrorMessage.for_response(
        code: response.code, body: response.body, context: 'search', account_id: @account_id
      )
    )
  end

  def lead_for(place)
    attributes = place_attributes(place).merge(url_attributes(place)).merge(address_attributes(place)).merge(place_signals(place))
    fit_text_columns(attributes)
  end

  def place_attributes(place)
    reviews = Array(place['reviews']).first(5)
    {
      provider: 'google_places',
      provider_place_id: place['id'],
      name: place.dig('displayName', 'text').presence || 'Google Places lead',
      phone: place['internationalPhoneNumber'].presence || place['nationalPhoneNumber'],
      address: place['formattedAddress'].to_s,
      latitude: place.dig('location', 'latitude'),
      longitude: place.dig('location', 'longitude'),
      rating: place['rating'],
      reviews_count: place['userRatingCount'],
      category: Array(place['types']).first,
      metadata: reviews.present? ? { reviews_snapshot: reviews } : {},
      raw_payload: place
    }
  end

  # Texto do Google maior que a coluna é cortado em vez de derrubar a busca (#723).
  def fit_text_columns(attributes)
    attributes.merge(TEXT_COLUMNS.index_with { |column| Autonomia::Prospecting::ColumnFit.text(attributes[column]) })
  end

  # URLs que cabem na coluna, sem derrubar a busca (#723).
  def url_attributes(place)
    {
      website: Autonomia::Prospecting::ColumnFit.url(place['websiteUri']),
      google_maps_uri: Autonomia::Prospecting::ColumnFit.url(place['googleMapsUri'], drop_query: false)
    }
  end

  def address_attributes(place)
    components = Array(place['addressComponents'])
    {
      neighborhood: component_text(components, NEIGHBORHOOD_TYPES, 'longText'),
      city: component_text(components, CITY_TYPES, 'longText'),
      state: component_text(components, ['administrative_area_level_1'], 'shortText'),
      country: component_text(components, ['country'], 'shortText') || @country
    }
  end

  # Primeiro tipo da lista que aparece no endereço.
  def component_text(components, types, text_key)
    types.each do |type|
      component = components.find { |item| Array(item['types']).include?(type) }
      return component[text_key].presence || component['longText'] if component
    end
    nil
  end

  def place_signals(place)
    photos = Array(place['photos'])
    current_hours = place['currentOpeningHours'].to_h
    {
      has_photos: photos.any?,
      photo_count: photos.size,
      open_now: current_hours.key?('openNow') ? current_hours['openNow'] : nil,
      has_opening_hours: place['regularOpeningHours'].present?
    }
  end
end
