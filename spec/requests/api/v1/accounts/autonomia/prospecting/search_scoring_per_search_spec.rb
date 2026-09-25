require 'rails_helper'

# Nota e prioridade também são da busca (#678), como a posição no Google já era (#677). O lead é um só por conta e
# guarda os valores da busca mais recente; reabrir uma busca antiga mostra os dela.
RSpec.describe 'Autonomia prospecting scoring per search', type: :request do
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

  def create_search(query, score_mode: 'gbp')
    post searches_path,
         params: { search: { query: query, location: 'Curitiba, PR', requested_limit: 8, metadata: { score_mode: score_mode } } },
         headers: auth_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body['payload']
  end

  def values_by_name(leads)
    leads.to_h { |lead| [lead['name'], lead.slice('score', 'priority_score', 'priority_position', 'score_breakdown')] }
  end

  it 'reabrir a busca antiga mostra a nota e a prioridade dela, não as da busca mais recente' do
    stub_google(fixture['places'])
    first = create_search('padaria')
    first_values = values_by_name(first['leads'])
    stub_google(fixture['places'].last(3).reverse)
    second = create_search('padaria no batel', score_mode: 'general')

    expect(values_by_name(second['leads'])).not_to eq(first_values.slice(*values_by_name(second['leads']).keys))

    get "#{searches_path}/#{first.dig('search', 'id')}", headers: auth_headers(admin)

    expect(values_by_name(response.parsed_body.dig('payload', 'leads'))).to eq(first_values)
    expect(response.parsed_body.dig('payload', 'leads').pluck('priority_position').sort).to eq((1..8).to_a)
  end

  it 'a busca servida do cache mostra a nota e a prioridade da busca de origem' do
    Autonomia::Prospecting::Setting.for_account(account).update!(cache_ttl_seconds: 3600)
    stub_google(fixture['places'])
    first_values = values_by_name(create_search('padaria')['leads'])
    stub_google(fixture['places'].last(3).reverse)
    create_search('padaria no batel', score_mode: 'general')

    cached = create_search('padaria')

    expect(cached.dig('search', 'summary', 'cached_from_search_id')).to be_present
    expect(values_by_name(cached['leads'])).to eq(first_values)
  end

  it 'busca gravada antes desta mudança, sem os valores no metadata, usa os do lead' do
    stub_google(fixture['places'])
    search_id = create_search('padaria').dig('search', 'id')
    search = Autonomia::Prospecting::Search.find(search_id)
    search.update!(metadata: search.metadata.except('lead_scoring'))
    lead = search.leads.first
    lead.update_columns(priority_position: 99) # rubocop:disable Rails/SkipsModelValidations

    get "#{searches_path}/#{search_id}", headers: auth_headers(admin)

    payload_lead = response.parsed_body.dig('payload', 'leads').find { |item| item['id'] == lead.id }
    expect(payload_lead['priority_position']).to eq(99)
  end
end
