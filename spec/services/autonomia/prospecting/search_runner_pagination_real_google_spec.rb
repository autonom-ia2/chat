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

  # Nota, prioridade e posição são da busca (#678): o lead é um só por conta e guarda os valores da busca mais recente.
  it 'guarda nota, detalhe da nota e prioridade de cada lead na própria busca' do
    result = run_search(requested_limit: 20)

    scoring = result.search.metadata['lead_scoring']
    expect(scoring.keys).to match_array(result.leads.map { |lead| lead.id.to_s })
    lead = result.leads.first
    expect(scoring[lead.id.to_s]).to eq(
      'score' => lead.score.to_f,
      'score_breakdown' => lead.score_breakdown,
      'priority_score' => lead.priority_score.to_f,
      'priority_position' => lead.priority_position
    )
    expect(scoring.values.pluck('priority_position').sort).to eq((1..20).to_a)
  end

  describe 'quando o Google falha no meio' do
    let(:unavailable) { { status: 503, body: { error: { code: 503, status: 'UNAVAILABLE', message: 'fora' } }.to_json } }

    def fail_pages(failing)
      WebMock.reset!
      stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT).to_return do |request|
        body = JSON.parse(request.body)
        requests << body
        next unavailable if failing.call(body)

        { status: 200, body: page_for(body['pageToken']).to_json, headers: { 'Content-Type' => 'application/json' } }
      end
    end

    # Antes: a busca inteira falhava, os 20 lugares da página 1 sumiam e as 2 chamadas pagas não entravam no uso.
    it 'página seguinte fora do ar: a busca termina com a página 1, parcial, e as duas chamadas contadas' do
      fail_pages(->(body) { body.key?('pageToken') })

      result = run_search(requested_limit: 40)

      expect(requests.size).to eq(2)
      expect(result.search).to be_completed
      expect(result.search.consumed_api_units).to eq(2)
      expect(result.leads.map(&:provider_place_id)).to eq(pages.first['places'].pluck('id'))
      expect(result.search.metadata['partial_results']).to be(true)
      expect(result.search.cache_expires_at).to be_nil
    end

    it 'busca completa não fica marcada como parcial' do
      result = run_search(requested_limit: 20)

      expect(result.search.metadata['partial_results']).to be(false)
    end

    it 'primeira página fora do ar: a busca falha, mas a chamada paga entra no uso' do
      fail_pages(->(_body) { true })

      expect { run_search(requested_limit: 40) }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError)

      search = Autonomia::Prospecting::Search.where(account: account).last
      expect(search).to be_failed
      expect(search.consumed_api_units).to eq(1)
    end

    it 'raio maior fora do ar na expansão: fica com o raio anterior, parcial, e soma todas as chamadas' do
      fail_pages(->(body) { body.dig('locationBias', 'circle', 'radius').to_f > 5000 })

      result = described_class.new(
        account: account, user: user,
        params: { query: 'pizzaria', location: 'São Paulo, SP', radius: 5000, requested_limit: 60,
                  metadata: { location_latitude: -23.55, location_longitude: -46.63, filters: { auto_expand_radius: true } },
                  advanced_filters: { has_website: 'no' } }
      ).perform

      expect(result.search).to be_completed
      expect(result.search.radius).to eq(5000)
      expect(result.leads.size).to eq(12)
      expect(result.search.consumed_api_units).to eq(4)
      expect(result.search.metadata['partial_results']).to be(true)
    end
  end
end
