require 'rails_helper'

# Área desenhada no motor da busca (#678, E2 frente B): o pedido ao Google, o recorte do polígono depois da posição
# no Google e a área na chave do cache.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }
  let(:mock_provider_class) { Autonomia::Prospecting::Providers::MockProvider }
  let(:google_endpoint) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }
  let(:u_path) do
    [
      { lat: -25.50, lng: -49.30 }, { lat: -25.50, lng: -49.20 }, { lat: -25.40, lng: -49.20 }, { lat: -25.40, lng: -49.23 },
      { lat: -25.45, lng: -49.23 }, { lat: -25.45, lng: -49.27 }, { lat: -25.40, lng: -49.27 }, { lat: -25.40, lng: -49.30 }
    ]
  end
  let(:bounds) { { north: -25.4, south: -25.5, east: -49.2, west: -49.3 } }

  before { setting.update!(provider: 'mock') }

  def place(id, latitude, longitude)
    { provider: 'mock', provider_place_id: "places/#{id}", name: "Lugar #{id}", phone: "+554199999000#{id.ord % 10}",
      latitude: latitude, longitude: longitude, rating: 4.5, reviews_count: 10, raw_payload: {} }
  end

  def run_search(params)
    described_class.new(account: account, user: user, params: params).perform
  end

  def polygon_params(path = u_path, **extra)
    { query: 'padaria', location: 'Curitiba, PR', requested_limit: 4, area_type: 'polygon', area_config: { path: path } }
      .merge(extra)
  end

  def google_request_body
    body = nil
    expect(a_request(:post, google_endpoint).with { |request| body = JSON.parse(request.body) }).to have_been_made.once
    body
  end

  def stub_google_places(places = [])
    stub_request(:post, google_endpoint)
      .to_return(status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'polígono' do
    let(:places) do
      [
        place('a', -25.42, -49.29), # braço esquerdo: dentro
        place('b', -25.42, -49.25), # vão do U: dentro do retângulo, fora do polígono
        place('c', -25.30, -49.25), # fora do retângulo
        place('d', -25.48, -49.25), # base do U: dentro
        place('e', nil, nil) # sem coordenada: não dá para provar que está dentro
      ]
    end

    before do
      allow(mock_provider_class).to receive(:new).and_return(instance_double(mock_provider_class, search: places))
    end

    it 'descarta quem está fora do polígono côncavo, inclusive no vão dentro do retângulo' do
      result = run_search(polygon_params(requested_limit: 5))

      expect(result.leads.map(&:provider_place_id)).to eq(%w[places/a places/d])
      expect(result.search.metadata['results_count']).to eq(2)
    end

    it 'atribui a posição no Google antes do recorte' do
      result = run_search(polygon_params(requested_limit: 5))

      expect(result.leads.map(&:search_rank)).to eq([1, 4])
      expect(result.search.metadata['lead_ranks'].values).to eq([1, 4])
    end

    it 'grava o tipo polígono, os pontos e o retângulo que o contém' do
      search = run_search(polygon_params).search

      expect(search.area_type).to eq('polygon')
      expect(search.area_config['path'].size).to eq(8)
      expect(search.area_config['bounds']).to eq('north' => -25.4, 'south' => -25.5, 'east' => -49.2, 'west' => -49.3)
      expect(search.area_config['label']).to eq('Curitiba, PR')
    end

    it 'recusa polígono com menos de três pontos, sem gravar busca' do
      expect { run_search(polygon_params(u_path.first(2))) }
        .to raise_error(ActiveRecord::RecordInvalid, /#{I18n.t('autonomia.prospecting.errors.drawn_area_required')}/)
      expect(account.autonomia_prospecting_searches.count).to eq(0)
    end
  end

  describe 'chave do cache' do
    before { setting.update!(cache_ttl_seconds: 3600) }

    it 'o mesmo polígono reaproveita a busca e outro polígono busca de novo' do
      first = run_search(polygon_params)
      same = run_search(polygon_params)
      moved = run_search(polygon_params(u_path.map { |point| point.merge(lng: point[:lng] + 0.01) }))

      expect(same.search).to be_cached
      expect(same.search.metadata['cached_from_search_id']).to eq(first.search.id)
      expect(moved.search).not_to be_cached
      expect(moved.search.cache_fingerprint).not_to eq(first.search.cache_fingerprint)
    end

    it 'o mesmo centro com tipo de área diferente não reaproveita a busca' do
      center = { lat: -25.45, lng: -49.25 }
      circle = run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 2, radius: 3000,
                          area_type: 'circle', area_config: { center: center })
      radius = run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 2, radius: 3000,
                          area_type: 'radius', area_config: { center: center })

      expect(radius.search).not_to be_cached
      expect(radius.search.cache_fingerprint).not_to eq(circle.search.cache_fingerprint)
    end
  end

  describe 'pedido ao Google' do
    before { setting.update!(provider: 'google_places') }

    it 'círculo desenhado vai como locationBias circle com o centro e o raio do desenho' do
      stub_google_places

      search = run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 1, radius: 3200,
                          area_type: 'circle', area_config: { center: { lat: -25.43, lng: -49.27 } }).search

      expect(google_request_body['locationBias']).to eq(
        'circle' => { 'center' => { 'latitude' => -25.43, 'longitude' => -49.27 }, 'radius' => 3200 }
      )
      expect(search.area_type).to eq('circle')
      expect(search.area_config).to include('center' => { 'lat' => -25.43, 'lng' => -49.27 }, 'radius' => 3200)
    end

    it 'círculo desenhado não expande o raio, mesmo com a expansão ligada' do
      stub_google_places

      run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 5, radius: 1000, area_type: 'circle',
                 area_config: { center: { lat: -25.43, lng: -49.27 } }, metadata: { filters: { auto_expand_radius: true } })

      expect(a_request(:post, google_endpoint)).to have_been_made.once
    end

    it 'retângulo desenhado vai como locationBias rectangle, como no Orth' do
      stub_google_places

      run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 1, area_type: 'rectangle',
                 area_config: { bounds: bounds })

      body = google_request_body
      expect(body).not_to have_key('locationRestriction')
      expect(body['locationBias']).to eq(
        'rectangle' => { 'low' => { 'latitude' => -25.5, 'longitude' => -49.3 },
                         'high' => { 'latitude' => -25.4, 'longitude' => -49.2 } }
      )
    end

    it 'polígono pede o retângulo que o contém e recorta a resposta do Google' do
      inside = { 'id' => 'places/in', 'displayName' => { 'text' => 'Dentro' }, 'location' => { 'latitude' => -25.48, 'longitude' => -49.25 } }
      notch = { 'id' => 'places/gap', 'displayName' => { 'text' => 'Vão' }, 'location' => { 'latitude' => -25.42, 'longitude' => -49.25 } }
      stub_google_places([notch, inside])

      result = run_search(polygon_params(requested_limit: 2))

      expect(google_request_body['locationBias']['rectangle']).to eq(
        'low' => { 'latitude' => -25.5, 'longitude' => -49.3 }, 'high' => { 'latitude' => -25.4, 'longitude' => -49.2 }
      )
      expect(result.leads.map(&:provider_place_id)).to eq(['places/in'])
      expect(result.leads.first.search_rank).to eq(2)
    end
  end
end
