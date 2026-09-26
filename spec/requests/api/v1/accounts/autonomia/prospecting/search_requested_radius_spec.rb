require 'rails_helper'

# Repetir ou editar uma busca do histórico (#678) refaz o pedido original. Com a expansão de raio do Orth (#732 item 4),
# o raio gravado na busca é o que a expansão alcançou quando ela trouxe mais; o payload também traz o raio que a pessoa
# pediu e a marca de raio ampliado.
RSpec.describe 'Autonomia prospecting search requested radius', type: :request do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }
  let(:search_params) do
    {
      search: {
        query: 'padaria', location: 'Curitiba, PR', radius: 1000, requested_limit: 5,
        metadata: { location_latitude: -25.43, location_longitude: -49.27 }
      }
    }
  end

  # Um lugar no raio pedido e dois no dobro dele: a expansão traz mais e fica.
  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT).to_return do |request|
      count = JSON.parse(request.body).dig('locationBias', 'circle', 'radius') == 1000 ? 1 : 2
      places = Array.new(count) { |index| { id: "places/p#{index}", displayName: { text: "Padaria #{index}" }, formattedAddress: 'Curitiba, PR' } }
      { status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'devolve o raio pedido ao lado do raio expandido' do
    post searches_path, params: search_params, headers: auth_headers(admin), as: :json
    search_id = response.parsed_body.dig('payload', 'search', 'id')

    get "#{searches_path}/#{search_id}", headers: auth_headers(admin)

    expect(response.parsed_body['payload']).to include('radius' => 2000, 'requested_radius' => 1000)
    expect(response.parsed_body.dig('payload', 'summary', 'radius_expanded')).to be(true)
  end

  it 'mantém o raio pedido quando a busca repetida vem do cache' do
    Autonomia::Prospecting::Setting.for_account(account).update!(cache_ttl_seconds: 3600)
    post searches_path, params: search_params, headers: auth_headers(admin), as: :json
    post searches_path, params: search_params, headers: auth_headers(admin), as: :json
    cached = Autonomia::Prospecting::Search.find(response.parsed_body.dig('payload', 'search', 'id'))

    get "#{searches_path}/#{cached.id}", headers: auth_headers(admin)

    expect(cached.status).to eq('cached')
    expect(response.parsed_body['payload']).to include('radius' => 2000, 'requested_radius' => 1000)
    expect(cached.metadata['radius_expanded']).to be(true)
  end
end
