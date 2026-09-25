require 'rails_helper'

# Busca paginada de ponta a ponta (#678, E2 frente A) com as três páginas REAIS do Google Places de "pizzaria em São
# Paulo" (ver google_places_provider_pagination_spec.rb). Prova: três chamadas encadeadas pelo pageToken, posição no
# Google de 1 a 60 sem buraco, filtro aplicado página a página antes do corte, uma unidade por página e nenhuma chamada
# ao Google com transação do banco aberta.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pages) do
    (1..3).map { |number| JSON.parse(file_fixture("google_places/search_text_real_pizzaria_sp_p#{number}.json").read) }
  end
  let(:all_places) { pages.flat_map { |page| page['places'] } }
  let(:requests) { [] }
  let(:open_transactions_during_calls) { [] }

  before do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT).to_return do |request|
      body = JSON.parse(request.body)
      requests << body['pageToken']
      open_transactions_during_calls << ActiveRecord::Base.connection.open_transactions
      { status: 200, body: page_for(body['pageToken']).to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def page_for(token)
    return pages.first if token.nil?

    pages[pages.index { |page| page['nextPageToken'] == token } + 1]
  end

  def run_search(requested_limit:, advanced_filters: {})
    described_class.new(
      account: account,
      user: user,
      params: { query: 'pizzaria', location: 'São Paulo, SP', requested_limit: requested_limit, advanced_filters: advanced_filters }
    ).perform
  end

  def google_rank_of(place_id)
    all_places.index { |place| place['id'] == place_id } + 1
  end

  it 'pede 60 e entrega os 60 lugares, na ordem do Google, com posição de 1 a 60 sem buraco' do
    result = run_search(requested_limit: 60)

    expect(requests).to eq([nil, pages[0]['nextPageToken'], pages[1]['nextPageToken']])
    expect(result.search.consumed_api_units).to eq(3)
    expect(result.leads.map(&:provider_place_id)).to eq(all_places.pluck('id'))
    expect(result.leads.map(&:search_rank)).to eq((1..60).to_a)
    expect(result.search.metadata['lead_ranks'].values.sort).to eq((1..60).to_a)
    expect(result.search.metadata['results_count']).to eq(60)
  end

  it 'pede 25 e para na segunda página' do
    result = run_search(requested_limit: 25)

    expect(requests.size).to eq(2)
    expect(result.search.consumed_api_units).to eq(2)
    expect(result.leads.map(&:search_rank)).to eq((1..25).to_a)
  end

  it 'filtra cada página antes de cortar: 10 sem site pedem as três páginas e guardam a posição real' do
    result = run_search(requested_limit: 10, advanced_filters: { has_website: 'no' })

    without_site = all_places.select { |place| place['websiteUri'].blank? }
    expect(requests.size).to eq(3)
    expect(result.search.consumed_api_units).to eq(3)
    expect(result.leads.size).to eq(10)
    expect(result.leads.map(&:website)).to all(be_nil)
    expect(result.leads.map(&:provider_place_id)).to eq(without_site.first(10).pluck('id'))
    expect(result.leads.map(&:search_rank)).to eq(without_site.first(10).map { |place| google_rank_of(place['id']) })
  end

  it 'devolve min(pedido, quantos passam no filtro): 60 sem site viram os 12 que existem' do
    result = run_search(requested_limit: 60, advanced_filters: { has_website: 'no' })

    expect(requests.size).to eq(3)
    expect(result.leads.size).to eq(12)
  end

  it 'corta as 20 primeiras posições e pagina até a 60ª' do
    result = run_search(requested_limit: 60, advanced_filters: { outside_top: '20' })

    expect(requests.size).to eq(3)
    expect(result.leads.map(&:search_rank)).to eq((21..60).to_a)
  end

  it 'não pede a terceira página quando a faixa de posição termina na 40ª' do
    result = run_search(requested_limit: 60, advanced_filters: { search_rank_max: '40' })

    expect(requests.size).to eq(2)
    expect(result.leads.map(&:search_rank)).to eq((1..40).to_a)
  end

  it 'não chama o Google com transação do banco aberta' do
    baseline = ActiveRecord::Base.connection.open_transactions

    run_search(requested_limit: 60)

    expect(open_transactions_during_calls).to eq([baseline] * 3)
  end
end
