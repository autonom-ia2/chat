require 'rails_helper'

# Repetir uma busca do histórico (#678) chama o Google de novo, como no Orth, que não tem cache de busca. Uma busca
# nova igual dentro do prazo do cache continua servida do cache.
RSpec.describe 'Autonomia prospecting repeat search without cache', type: :request do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }
  let(:search_params) { { query: 'padaria', location: 'Curitiba, PR', radius: 1000, requested_limit: 1 } }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 3600)
    place = { id: 'places/p1', displayName: { text: 'Padaria 1' }, formattedAddress: 'Curitiba, PR' }
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: { places: [place] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def create_search(params)
    post searches_path, params: { search: params }, headers: auth_headers(admin), as: :json
    Autonomia::Prospecting::Search.find(response.parsed_body.dig('payload', 'search', 'id'))
  end

  it 'busca nova igual vem do cache' do
    create_search(search_params)
    second = create_search(search_params)

    expect(second.status).to eq('cached')
    expect(a_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)).to have_been_made.once
  end

  it 'Repetir (fresh) chama o Google de novo e não vira busca de cache' do
    create_search(search_params)
    repeated = create_search(search_params.merge(fresh: true))

    expect(repeated.status).to eq('completed')
    expect(a_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)).to have_been_made.twice
  end
end
