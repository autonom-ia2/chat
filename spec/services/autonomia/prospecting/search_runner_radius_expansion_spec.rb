require 'rails_helper'

# Expansão de raio como a do Orth (#732 item 4; LOCAL-18, FILTRO-17, MOTOR-03; app/api/search/route.ts): ligada por
# padrão, uma tentativa só com o dobro do raio, teto de 10 km, e a busca só fica com a expansão se ela trouxer mais
# lugares que passam nos filtros. As respostas são as páginas REAIS do Google Places de "pizzaria em São Paulo"
# (4 lugares sem site em cada página; a terceira não tem nextPageToken). O que muda entre os raios é qual página o
# Google devolve, escolhida pelo raio do locationBias do pedido.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pages) do
    (1..3).map { |number| JSON.parse(file_fixture("google_places/search_text_real_pizzaria_sp_p#{number}.json").read) }
  end
  let(:all_places) { pages.flat_map { |page| page['places'] } }
  let(:without_site) { all_places.select { |place| place['websiteUri'].blank? } }
  let(:requested_radii) { [] }
  let(:center) { { location_latitude: -23.55, location_longitude: -46.63 } }

  before do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
  end

  # answers: raio => :chain (as três páginas encadeadas) ou :last_page (só a terceira, sem token).
  def stub_google(answers)
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT).to_return do |request|
      body = JSON.parse(request.body)
      radius = body.dig('locationBias', 'circle', 'radius')
      requested_radii << radius
      page = answers.fetch(radius) == :last_page ? pages.last : page_for(body['pageToken'])
      { status: 200, body: page.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def page_for(token)
    return pages.first if token.nil?

    pages[pages.index { |page| page['nextPageToken'] == token } + 1]
  end

  def run_search(radius:, requested_limit:, filters: nil, metadata: center)
    search_metadata = filters.nil? ? metadata : metadata.merge(filters: filters)
    described_class.new(
      account: account, user: user,
      params: { query: 'pizzaria', location: 'São Paulo, SP', radius: radius, requested_limit: requested_limit,
                metadata: search_metadata, advanced_filters: { has_website: 'no' } }
    ).perform
  end

  describe 'só fica com a expansão quando ela traz mais' do
    it 'fica com o dobro do raio quando ele traz mais lugares que passam nos filtros' do
      stub_google(1000 => :last_page, 2000 => :chain)

      result = run_search(radius: 1000, requested_limit: 10)

      expect(requested_radii).to eq([1000, 2000, 2000, 2000])
      expect(result.search.radius).to eq(2000)
      expect(result.search.area_config['radius']).to eq(2000)
      expect(result.search.metadata).to include('radius_expanded' => true, 'requested_radius' => 1000, 'partial_results' => false)
      expect(result.leads.map(&:provider_place_id)).to eq(without_site.first(10).pluck('id'))
      expect(result.search.consumed_api_units).to eq(4)
    end

    it 'mantém o raio original quando a expansão traz menos, e a chamada paga entra no uso' do
      stub_google(1000 => :chain, 2000 => :last_page)

      result = run_search(radius: 1000, requested_limit: 20)

      expect(requested_radii).to eq([1000, 1000, 1000, 2000])
      expect(result.search.radius).to eq(1000)
      expect(result.search.metadata).to include('radius_expanded' => false, 'requested_radius' => 1000)
      expect(result.leads.map(&:provider_place_id)).to eq(without_site.pluck('id'))
      expect(result.search.consumed_api_units).to eq(4)
    end

    it 'mantém o raio original quando a expansão traz a mesma quantidade' do
      stub_google(1000 => :chain, 2000 => :chain)

      result = run_search(radius: 1000, requested_limit: 20)

      expect(requested_radii).to eq([1000, 1000, 1000, 2000, 2000, 2000])
      expect(result.search.radius).to eq(1000)
      expect(result.search.metadata['radius_expanded']).to be(false)
      expect(result.leads.size).to eq(12)
    end

    it 'não tenta expandir quando o raio original já completa o pedido' do
      stub_google(1000 => :chain)

      result = run_search(radius: 1000, requested_limit: 8)

      expect(requested_radii).to eq([1000, 1000])
      expect(result.search.metadata['radius_expanded']).to be(false)
    end
  end

  describe 'uma tentativa só, com teto de 10 km' do
    it 'tenta uma vez só, mesmo quando a expansão ainda não completa o pedido' do
      stub_google(1000 => :last_page, 2000 => :last_page)

      run_search(radius: 1000, requested_limit: 20)

      expect(requested_radii).to eq([1000, 2000])
    end

    it 'o dobro de 8 km para em 10 km' do
      stub_google(8000 => :last_page, 10_000 => :chain)

      result = run_search(radius: 8000, requested_limit: 10)

      expect(requested_radii.uniq).to eq([8000, 10_000])
      expect(result.search.radius).to eq(10_000)
      expect(result.search.metadata['radius_expanded']).to be(true)
    end

    it 'raio de 10 km ou mais não expande' do
      stub_google(10_000 => :last_page, 15_000 => :last_page)

      run_search(radius: 10_000, requested_limit: 20)
      run_search(radius: 15_000, requested_limit: 20)

      expect(requested_radii).to eq([10_000, 15_000])
    end
  end

  describe 'ligada por padrão, com a caixa para desligar' do
    it 'expande quando a busca não diz nada sobre a expansão' do
      stub_google(1000 => :last_page, 2000 => :chain)

      result = run_search(radius: 1000, requested_limit: 10)

      expect(result.search.metadata['radius_expanded']).to be(true)
    end

    it 'não expande com a caixa desmarcada' do
      stub_google(1000 => :last_page)

      result = run_search(radius: 1000, requested_limit: 10, filters: { auto_expand_radius: false })

      expect(requested_radii).to eq([1000])
      expect(result.search.metadata['radius_expanded']).to be(false)
    end

    it 'não expande sem centro: sem o círculo, o raio não muda o que o Google devolve' do
      stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
        .to_return(status: 200, body: pages.last.to_json, headers: { 'Content-Type' => 'application/json' })

      run_search(radius: 1000, requested_limit: 10, metadata: {})

      expect(a_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)).to have_been_made.once
    end
  end
end
