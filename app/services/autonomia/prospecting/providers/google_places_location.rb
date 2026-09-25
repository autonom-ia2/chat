require 'json'

# Autocomplete e detalhe do local da busca no Google Places (New), no país da conta (#677). Erro do Google sobe como
# ProviderError com frase nossa em português; antes a tela recebia lista vazia e ninguém sabia por quê.
class Autonomia::Prospecting::Providers::GooglePlacesLocation
  AUTOCOMPLETE_ENDPOINT = 'https://places.googleapis.com/v1/places:autocomplete'.freeze
  PLACE_DETAILS_ENDPOINT = 'https://places.googleapis.com/v1/places'.freeze
  AUTOCOMPLETE_FIELD_MASK = 'suggestions.placePrediction.text,suggestions.placePrediction.placeId'.freeze
  DETAILS_FIELD_MASK = 'id,displayName,formattedAddress,location'.freeze
  INCLUDED_PRIMARY_TYPES = %w[locality sublocality administrative_area_level_2].freeze
  MAX_SUGGESTIONS = 8
  TIMEOUT_SECONDS = 8

  def initialize(api_key:, country:, account_id:)
    @api_key = api_key.to_s
    @country = Autonomia::Prospecting::SearchCountry.normalize(country) || Autonomia::Prospecting::SearchCountry::DEFAULT
    @account_id = account_id
  end

  def suggestions(query)
    response = request('autocomplete') do
      HTTParty.post(AUTOCOMPLETE_ENDPOINT, body: autocomplete_body(query).to_json,
                                           headers: headers(AUTOCOMPLETE_FIELD_MASK), timeout: TIMEOUT_SECONDS)
    end

    Array(response['suggestions'])
      .filter_map { |item| suggestion_for(item['placePrediction'].to_h) }
      .uniq { |item| item[:place_id] }
      .first(MAX_SUGGESTIONS)
  end

  def details(place_id)
    body = request('details') do
      HTTParty.get("#{PLACE_DETAILS_ENDPOINT}/#{place_id}", query: locale_params,
                                                            headers: headers(DETAILS_FIELD_MASK), timeout: TIMEOUT_SECONDS)
    end

    {
      place_id: body['id'],
      label: body['formattedAddress'].presence || body.dig('displayName', 'text'),
      latitude: body.dig('location', 'latitude'),
      longitude: body.dig('location', 'longitude')
    }
  end

  private

  def autocomplete_body(query)
    {
      input: query,
      includedPrimaryTypes: INCLUDED_PRIMARY_TYPES,
      includedRegionCodes: [@country.downcase]
    }.merge(locale_params)
  end

  def locale_params
    { languageCode: Autonomia::Prospecting::SearchCountry.language_code(@country), regionCode: @country }
  end

  def headers(field_mask)
    {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }
  end

  def suggestion_for(prediction)
    text = prediction.dig('text', 'text')
    place_id = prediction['placeId']
    return if text.blank? || place_id.blank?

    { text: text, place_id: place_id }
  end

  def request(context)
    response = yield
    unless response.success?
      raise provider_error(Autonomia::Prospecting::GoogleErrorMessage.for_response(
                             code: response.code, body: response.body, context: context, account_id: @account_id
                           ))
    end

    JSON.parse(response.body.to_s)
  rescue JSON::ParserError, *Autonomia::Prospecting::GoogleErrorMessage::NETWORK_ERRORS => e
    raise provider_error(Autonomia::Prospecting::GoogleErrorMessage.for_exception(e, context: context, account_id: @account_id))
  end

  def provider_error(message)
    Autonomia::Prospecting::SearchRunner::ProviderError.new(message)
  end
end
