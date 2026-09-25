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
    'places.regularOpeningHours.weekdayDescriptions'
  ].join(',').freeze
  # Teto do Google por chamada. Pedido maior só chega com a paginação da E2.
  MAX_RESULTS_PER_REQUEST = 20
  # Tipos de addressComponents, na ordem de preferência. Cidade sem locality é o município (administrative_area_level_2),
  # como no Orth (lib/services/search/search-filters.ts).
  NEIGHBORHOOD_TYPES = %w[sublocality_level_1 sublocality neighborhood].freeze
  CITY_TYPES = %w[locality administrative_area_level_2].freeze

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
  end

  def search
    response = HTTParty.post(
      ENDPOINT,
      body: request_body.to_json,
      headers: headers,
      timeout: 10
    )
    @api_units = 1

    raise provider_error(response) unless response.success?

    Array(JSON.parse(response.body)['places']).first(@limit).map { |place| lead_for(place) }
  rescue JSON::ParserError, *Autonomia::Prospecting::GoogleErrorMessage::NETWORK_ERRORS => e
    raise Autonomia::Prospecting::SearchRunner::ProviderError,
          Autonomia::Prospecting::GoogleErrorMessage.for_exception(e, context: 'search', account_id: @account_id)
  end

  private

  def request_body
    {
      textQuery: [@query, @location].compact_blank.join(' '),
      maxResultCount: [@limit, MAX_RESULTS_PER_REQUEST].min,
      languageCode: Autonomia::Prospecting::SearchCountry.language_code(@country),
      regionCode: @country
    }.merge(location_bias_payload)
  end

  def location_bias_payload
    rectangle = rectangle_bias
    return { locationBias: { rectangle: rectangle } } if rectangle.present?

    circle = circle_bias
    return { locationBias: { circle: circle } } if circle.present?

    {}
  end

  def rectangle_bias
    return unless @area_type == 'viewport'

    bounds = @area_config['bounds']
    return if bounds.blank?

    {
      low: {
        latitude: bounds['south'].to_f,
        longitude: bounds['west'].to_f
      },
      high: {
        latitude: bounds['north'].to_f,
        longitude: bounds['east'].to_f
      }
    }
  end

  def circle_bias
    center = @area_config['center']
    return if center.blank?

    {
      center: {
        latitude: center['lat'].to_f,
        longitude: center['lng'].to_f
      },
      radius: [@radius, 50_000].min
    }
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
    reviews = Array(place['reviews']).first(5)
    {
      provider: 'google_places',
      provider_place_id: place['id'],
      name: place.dig('displayName', 'text').presence || 'Google Places lead',
      phone: place['internationalPhoneNumber'].presence || place['nationalPhoneNumber'],
      website: place['websiteUri'],
      address: place['formattedAddress'].to_s,
      google_maps_uri: place['googleMapsUri'],
      latitude: place.dig('location', 'latitude'),
      longitude: place.dig('location', 'longitude'),
      rating: place['rating'],
      reviews_count: place['userRatingCount'],
      category: Array(place['types']).first,
      metadata: reviews.present? ? { reviews_snapshot: reviews } : {},
      raw_payload: place
    }.merge(address_attributes(place)).merge(place_signals(place))
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
