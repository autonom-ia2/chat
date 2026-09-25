require 'rails_helper'

# País da busca (#677) depois da aba Score da E5 (#681, frente C): conta que nunca escolheu país continua no Brasil,
# e salvar a nota não apaga o país. O Brasil chega ao autocomplete do local e à busca no Google.
RSpec.describe 'Autonomia prospecting: país padrão da busca', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:autocomplete_url) { Autonomia::Prospecting::Providers::GooglePlacesLocation::AUTOCOMPLETE_ENDPOINT }
  let(:search_url) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }
  let(:own_profile) { Autonomia::Prospecting::ScoringProfile.create!(name: 'Exclusivo', account_ids: [account.id]) }

  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account)
    # A aba Score salva a nota sem falar do país, como a tela faz quando o país não mudou.
    patch "#{base_url}/settings", params: { settings: { scoring_mode: 'profile', scoring_profile_id: own_profile.id } },
                                  headers: auth_headers
  end

  def auth_headers
    { 'api_access_token' => admin.access_token.token }
  end

  it 'continua no Brasil depois de salvar a aba Score' do
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'search_country')).to eq('BR')
    expect(Autonomia::Prospecting::Setting.for_account(account).metadata.to_h).not_to have_key('search_country')
  end

  it 'leva o Brasil ao autocomplete do local' do
    stub_request(:post, autocomplete_url).to_return(status: 200, body: { suggestions: [] }.to_json)

    get "#{base_url}/searches/location_suggestions", params: { query: 'Curit' }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(
      a_request(:post, autocomplete_url).with do |request|
        JSON.parse(request.body).slice('includedRegionCodes', 'languageCode', 'regionCode') ==
          { 'includedRegionCodes' => ['br'], 'languageCode' => 'pt-BR', 'regionCode' => 'BR' }
      end
    ).to have_been_made
  end

  it 'leva o Brasil à busca no Google' do
    stub_request(:post, search_url).to_return(status: 200, body: { places: [] }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

    post "#{base_url}/searches",
         params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 1,
                             metadata: { location_place_id: 'places/curitiba', location_latitude: -25.4284,
                                         location_longitude: -49.2733, location_label: 'Curitiba, PR, Brasil' } } },
         headers: auth_headers

    expect(response).to have_http_status(:created)
    expect(
      a_request(:post, search_url).with do |request|
        JSON.parse(request.body).slice('languageCode', 'regionCode') == { 'languageCode' => 'pt-BR', 'regionCode' => 'BR' }
      end
    ).to have_been_made.at_least_once
  end
end
