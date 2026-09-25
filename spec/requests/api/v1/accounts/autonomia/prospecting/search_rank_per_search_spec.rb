require 'rails_helper'

# O lead é um só por conta, e a posição no Google gravada nele é a da busca mais recente (#677). A busca guarda a
# posição de cada lead dela, e o payload da busca usa essa, para o card, a gaveta e o refino por faixa de posição.
RSpec.describe 'Autonomia prospecting search rank per search', type: :request do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }
  let(:google_endpoint) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }
  let(:fixture) { JSON.parse(file_fixture('google_places/search_text_filtros.json').read) }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
  end

  def stub_google(places)
    stub_request(:post, google_endpoint)
      .to_return(status: 200, body: fixture.merge('places' => places).to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def create_search(query)
    post searches_path,
         params: { search: { query: query, location: 'Curitiba, PR', requested_limit: 8 } },
         headers: auth_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body.dig('payload', 'search', 'id')
  end

  def ranks_by_name(leads)
    leads.to_h { |lead| [lead['name'], lead['search_rank']] }
  end

  it 'reabrir a busca antiga mostra a posição dela, não a da busca mais recente' do
    stub_google(fixture['places'])
    first_search_id = create_search('padaria')
    stub_google(fixture['places'].reverse)
    create_search('padaria no batel')

    expect(ranks_by_name(response.parsed_body.dig('payload', 'leads'))['Padaria Exemplo C']).to eq(6)

    get "#{searches_path}/#{first_search_id}", headers: auth_headers(admin)

    ranks = ranks_by_name(response.parsed_body.dig('payload', 'leads'))
    expect(ranks['Padaria Exemplo A']).to eq(1)
    expect(ranks['Padaria Exemplo C']).to eq(3)
    expect(ranks['Padaria Exemplo H']).to eq(8)
  end

  it 'a busca servida do cache mostra a posição da busca de origem' do
    Autonomia::Prospecting::Setting.for_account(account).update!(cache_ttl_seconds: 3600)
    stub_google(fixture['places'])
    create_search('padaria')
    stub_google(fixture['places'].reverse)
    create_search('padaria no batel')

    create_search('padaria')

    expect(response.parsed_body.dig('payload', 'search', 'summary', 'cached_from_search_id')).to be_present
    expect(ranks_by_name(response.parsed_body.dig('payload', 'leads'))['Padaria Exemplo C']).to eq(3)
  end

  it 'busca gravada antes desta mudança, sem as posições no metadata, usa a posição do lead' do
    stub_google(fixture['places'])
    search_id = create_search('padaria')
    search = Autonomia::Prospecting::Search.find(search_id)
    search.update!(metadata: search.metadata.except('lead_ranks'))

    get "#{searches_path}/#{search_id}", headers: auth_headers(admin)

    expect(ranks_by_name(response.parsed_body.dig('payload', 'leads'))['Padaria Exemplo C']).to eq(3)
  end
end
