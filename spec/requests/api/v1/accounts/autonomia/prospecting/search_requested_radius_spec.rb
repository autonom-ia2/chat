require 'rails_helper'

# Repetir ou editar uma busca do histórico (#678) refaz o pedido original. Com "Expandir raio", o raio gravado na busca
# é o que a expansão alcançou; o payload também traz o raio que a pessoa pediu.
RSpec.describe 'Autonomia prospecting search requested radius', type: :request do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
    place = { id: 'places/p1', displayName: { text: 'Padaria 1' }, formattedAddress: 'Curitiba, PR' }
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: { places: [place] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'devolve o raio pedido ao lado do raio expandido' do
    post searches_path,
         params: {
           search: {
             query: 'padaria', location: 'Curitiba, PR', radius: 1000, requested_limit: 5,
             metadata: { filters: { auto_expand_radius: true } }
           }
         },
         headers: auth_headers(admin),
         as: :json
    search_id = response.parsed_body.dig('payload', 'search', 'id')

    get "#{searches_path}/#{search_id}", headers: auth_headers(admin)

    expect(response.parsed_body['payload']).to include('radius' => 4000, 'requested_radius' => 1000)
  end
end
