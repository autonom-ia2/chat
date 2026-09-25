require 'rails_helper'

# Paginação do Google Places (#678, E2 frente A), com as três páginas REAIS de "pizzaria em São Paulo" gravadas na
# Places API (New) searchText em 25/09/2026. Da gravação saíram os dados de pessoas (autor das avaliações e das fotos).
# Contagens das próprias páginas: 20 lugares cada, 60 ids únicos; 4 sem websiteUri em cada página; a página 1 e a 2
# trazem nextPageToken, a 3 não.
RSpec.describe Autonomia::Prospecting::Providers::GooglePlacesProvider do
  let(:pages) do
    (1..3).map { |number| JSON.parse(file_fixture("google_places/search_text_real_pizzaria_sp_p#{number}.json").read) }
  end
  let(:requests) { [] }

  before do
    stub_request(:post, described_class::ENDPOINT).to_return do |request|
      body = JSON.parse(request.body)
      requests << body
      page = page_for(body['pageToken'])
      { status: 200, body: page.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Página 1 sem token; as seguintes só com o token que a anterior devolveu.
  def page_for(token)
    return pages.first if token.nil?

    index = pages.index { |page| page['nextPageToken'] == token }
    raise "pageToken desconhecido: #{token.to_s.first(12)}" if index.nil?

    pages[index + 1]
  end

  def provider(limit:)
    described_class.new(query: 'pizzaria', location: 'São Paulo, SP', radius: 5000, limit: limit, api_key: 'chave')
  end

  def all_ids
    pages.flat_map { |page| page['places'].pluck('id') }
  end

  it 'pede 60: três chamadas encadeando o pageToken, pageSize 20 e uma unidade por página' do
    search_provider = provider(limit: 60)

    results = search_provider.search

    expect(requests.size).to eq(3)
    expect(requests.pluck('pageToken')).to eq([nil, pages[0]['nextPageToken'], pages[1]['nextPageToken']])
    expect(requests.pluck('pageSize')).to all(eq(20))
    expect(requests).to all(satisfy { |body| !body.key?('maxResultCount') })
    expect(search_provider.api_units).to eq(3)
    expect(results.pluck(:provider_place_id)).to eq(all_ids)
    expect(all_ids.uniq.size).to eq(60)
  end

  it 'repete termo, país e área em todas as páginas' do
    provider(limit: 60).search

    fixed = requests.map { |body| body.except('pageToken') }
    expect(fixed.uniq.size).to eq(1)
  end

  it 'pede nextPageToken no FieldMask, senão o Google nem devolve o token' do
    provider(limit: 60).search

    expect(
      a_request(:post, described_class::ENDPOINT).with do |request|
        request.headers['X-Goog-Fieldmask'].split(',').include?('nextPageToken')
      end
    ).to have_been_made.times(3)
  end

  it 'pede 10 sem filtro: uma página basta e ela volta inteira, o corte é de quem chama' do
    search_provider = provider(limit: 10)

    results = search_provider.search

    expect(requests.size).to eq(1)
    expect(search_provider.api_units).to eq(1)
    expect(results.size).to eq(20)
  end

  it 'continua paginando enquanto o filtro de quem chama não completa o pedido' do
    search_provider = provider(limit: 10)
    accepted_ranks = []

    results = search_provider.search do |attributes, rank|
      accepted = attributes[:website].blank?
      accepted_ranks << rank if accepted
      accepted
    end

    # 4 sem site por página: 4, 8, 12. Só na terceira página o pedido de 10 fecha.
    expect(requests.size).to eq(3)
    expect(search_provider.api_units).to eq(3)
    expect(results.size).to eq(60)
    expect(accepted_ranks.size).to eq(12)
    expect(accepted_ranks.map { |rank| results[rank - 1][:website] }).to all(be_nil)
  end

  it 'para quando o filtro fecha o pedido antes da última página' do
    search_provider = provider(limit: 5)

    search_provider.search { |attributes, _rank| attributes[:website].blank? }

    expect(requests.size).to eq(2)
    expect(search_provider.api_units).to eq(2)
  end

  it 'para quando o Google não manda mais token, mesmo sem completar o pedido' do
    search_provider = provider(limit: 60)

    results = search_provider.search { |attributes, _rank| attributes[:website].blank? }

    expect(requests.size).to eq(3)
    expect(results.size).to eq(60)
  end

  it 'não passa da posição máxima pedida por quem chama' do
    search_provider = provider(limit: 60)

    results = search_provider.search(max_results: 20)

    expect(requests.size).to eq(1)
    expect(results.size).to eq(20)
  end

  it 'nunca passa de 60 posições nem de 3 páginas' do
    search_provider = provider(limit: 60)

    results = search_provider.search(max_results: 500) { |_attributes, _rank| false }

    expect(requests.size).to eq(3)
    expect(results.size).to eq(60)
  end

  # Antes a falha numa página do meio derrubava a busca inteira: os 20 lugares já recebidos e as chamadas já pagas
  # sumiam. Agora a busca fica com o que chegou e marca que é parcial.
  def stub_second_page_failure
    WebMock.reset!
    stub_request(:post, described_class::ENDPOINT)
      .with { |request| !JSON.parse(request.body).key?('pageToken') }
      .to_return(status: 200, body: pages.first.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, described_class::ENDPOINT)
      .with { |request| JSON.parse(request.body).key?('pageToken') }
      .to_return(status: 503, body: { error: { code: 503, status: 'UNAVAILABLE', message: 'fora' } }.to_json)
  end

  it 'falha numa página do meio devolve os lugares já recebidos, conta as duas chamadas e marca parcial' do
    stub_second_page_failure
    search_provider = provider(limit: 60)

    results = search_provider.search

    expect(results.pluck(:provider_place_id)).to eq(pages.first['places'].pluck('id'))
    expect(search_provider.api_units).to eq(2)
    expect(search_provider).to be_partial
  end

  it 'busca inteira não fica marcada como parcial' do
    search_provider = provider(limit: 60)

    search_provider.search

    expect(search_provider).not_to be_partial
  end

  it 'falha na primeira página continua derrubando a busca, com a frase em português' do
    WebMock.reset!
    stub_request(:post, described_class::ENDPOINT)
      .to_return(status: 503, body: { error: { code: 503, status: 'UNAVAILABLE', message: 'fora' } }.to_json)
    search_provider = provider(limit: 60)

    expect { search_provider.search }
      .to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, 'O Google não respondeu a tempo. Tente de novo em alguns minutos.')
    expect(search_provider.api_units).to eq(1)
  end
end
