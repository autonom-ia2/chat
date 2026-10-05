require 'rails_helper'

# Nomes das campanhas da Meta (#1034): cache de 7 dias, lote ?ids= de até 50, erros da Graph.
RSpec.describe Crm::MetaAds::NameResolver do
  let(:account) { create(:account) }
  let(:resolver) { described_class.new(account) }
  let(:ad_fields) { described_class::FIELDS.fetch('ad') }
  let(:ad_id) { '120254710067060999' }
  let(:adset_id) { '120254710067060777' }
  let(:campaign_id) { '120254710067060416' }

  def stub_permissions(body)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def ad_body(id, name: 'Video 2')
    { id: id, name: name, adset: { id: adset_id, name: 'Conjunto 60+' }, campaign: { id: campaign_id, name: 'Viagem EUA' } }
  end

  describe '.meta_id?' do
    it 'aceita só dígitos entre 6 e 30 caracteres' do
      valid = ['120254710067060416', 120_254_710_067_060_416, '123456', '1' * 30]
      invalid = ['12345', '1' * 31, 'Viagem EUA', '12025471006706041a', '-120254710067', '１２３４５６７', '', nil, ['120254710067060416']]

      expect(valid.map { |value| described_class.meta_id?(value) }).to all(be(true))
      expect(invalid.map { |value| described_class.meta_id?(value) }).to all(be(false))
    end
  end

  context 'with an active credential' do
    let!(:connection) { create_meta_ads_connection(account) }

    it 'resolve um anúncio com conjunto e campanha numa chamada só e guarda os três no cache' do
      graph = stub_meta_objects(ids: [ad_id], fields: ad_fields, body: { ad_id => ad_body(ad_id) })

      result = resolver.resolve([ad_id], type: 'ad')

      expect(result).to eq(ad_id => { name: 'Video 2', type: 'ad', campaign_name: 'Viagem EUA', adset_name: 'Conjunto 60+' })
      expect(graph).to have_been_requested.once
      cache = Crm::MetaAdObject.where(account_id: account.id).pluck(:meta_object_id, :object_type, :name).sort
      expect(cache).to eq([[campaign_id, 'campaign', 'Viagem EUA'], [ad_id, 'ad', 'Video 2'], [adset_id, 'adset', 'Conjunto 60+']].sort)
      expect(connection.reload.last_checked_at).to be_present
    end

    it 'usa o cache válido sem chamar a Graph' do
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Viagem EUA',
                                fetched_at: 6.days.ago)

      result = resolver.resolve([campaign_id], type: 'campaign')

      expect(result[campaign_id]).to include(name: 'Viagem EUA', type: 'campaign')
      expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'busca de novo o que passou de 7 dias e atualiza o nome' do
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Nome antigo',
                                fetched_at: 8.days.ago)
      graph = stub_meta_objects(ids: [campaign_id], fields: 'name', body: { campaign_id => { id: campaign_id, name: 'Nome novo' } })

      expect(resolver.resolve([campaign_id], type: 'campaign')[campaign_id][:name]).to eq('Nome novo')
      expect(graph).to have_been_requested.once
    end

    it 'manda só os IDs que faltam, em lotes de até 50' do
      cached = '900000000000000001'
      Crm::MetaAdObject.create!(account: account, meta_object_id: cached, object_type: 'campaign', name: 'Em cache', fetched_at: 1.day.ago)
      ids = (1..60).map { |n| (800_000_000_000_000_000 + n).to_s }
      first = stub_meta_objects(ids: ids.first(50), fields: 'name', body: ids.first(50).index_with { |id| { id: id, name: "C#{id}" } })
      second = stub_meta_objects(ids: ids.last(10), fields: 'name', body: ids.last(10).index_with { |id| { id: id, name: "C#{id}" } })

      result = resolver.resolve(ids + [cached], type: 'campaign')

      expect(result.size).to eq(61)
      expect(first).to have_been_requested.once
      expect(second).to have_been_requested.once
    end

    it 'ignora valores que não são ID sem chamar a Graph' do
      expect(resolver.resolve(['Viagem EUA', '{{ad.id}}', '', nil, '12345'], type: 'ad')).to eq({})
      expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'marca a credencial invalid em erro de permissão, sem lançar e sem resolver nada' do
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Viagem EUA',
                                fetched_at: 1.day.ago)
      stub_meta_objects(ids: [ad_id], fields: ad_fields, status: 400,
                        body: meta_graph_error(190, "Error validating access token: #{MetaAdsHelpers::TEST_TOKEN}"))

      result = nil
      expect { result = resolver.resolve([ad_id, campaign_id], type: 'ad') }.not_to raise_error

      expect(result).to eq({})
      connection.reload
      expect(connection.status).to eq('invalid')
      expect(connection.last_error).to be_present
      expect(connection.last_error).not_to include(MetaAdsHelpers::TEST_TOKEN)
    end

    [10, 200, 294].each do |code|
      it "código #{code} com ads_read revogada: confere /me/permissions e marca invalid" do
        stub_meta_objects(ids: [ad_id], fields: ad_fields, status: 403, body: meta_graph_error(code))
        check = stub_permissions({ data: [{ permission: 'ads_read', status: 'declined' }] })

        expect(resolver.resolve([ad_id], type: 'ad')).to eq({})
        expect(check).to have_been_requested.once
        expect(connection.reload.status).to eq('invalid')
      end
    end

    it 'código 10 num objeto de outra conta de anúncios, com ads_read concedida: erro só daquele ID' do
      foreign = '120254710067062222'
      batch = stub_meta_objects(ids: [ad_id, foreign], fields: ad_fields, status: 403, body: meta_graph_error(10))
      check = stub_permissions({ data: [{ permission: 'ads_read', status: 'granted' }] })
      stub_meta_objects(ids: [ad_id], fields: ad_fields, body: { ad_id => ad_body(ad_id) })
      single = stub_meta_objects(ids: [foreign], fields: ad_fields, status: 403, body: meta_graph_error(10))

      result = resolver.resolve([ad_id, foreign], type: 'ad')
      described_class.new(account).resolve([foreign], type: 'ad')

      expect(result.keys).to eq([ad_id])
      expect(connection.reload.status).to eq('active')
      expect(batch).to have_been_requested.once
      expect(check).to have_been_requested.once
      expect(single).to have_been_requested.once
    end

    it 'erro de um objeto derruba só aquele ID: refaz o lote um a um e ignora o que falhar' do
      missing = '120254710067061111'
      stub_meta_objects(ids: [ad_id, missing], fields: ad_fields, status: 400, body: meta_graph_error(100, 'Some aliases do not exist'))
      stub_meta_objects(ids: [ad_id], fields: ad_fields, body: { ad_id => ad_body(ad_id) })
      stub_meta_objects(ids: [missing], fields: ad_fields, status: 400, body: meta_graph_error(100, 'Object does not exist'))

      result = resolver.resolve([ad_id, missing], type: 'ad')

      expect(result.keys).to eq([ad_id])
      expect(connection.reload.status).to eq('active')
    end

    it 'cache negativo: o ID que a Meta não resolve não é buscado de novo por 7 dias' do
      graph = stub_meta_objects(ids: [campaign_id], fields: 'name', status: 400, body: meta_graph_error(100, 'Object does not exist'))

      3.times { expect(described_class.new(account).resolve([campaign_id], type: 'campaign')).to eq({}) }

      expect(graph).to have_been_requested.once
      expect(Crm::MetaAdObject.find_by(account_id: account.id, meta_object_id: campaign_id)).to have_attributes(name: nil,
                                                                                                                object_type: 'campaign')
    end

    it 'cache negativo mantém o nome já conhecido quando o anúncio deixa de existir' do
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Viagem EUA',
                                fetched_at: 8.days.ago)
      graph = stub_meta_objects(ids: [campaign_id], fields: 'name', status: 400, body: meta_graph_error(100, 'Object does not exist'))

      expect(resolver.resolve([campaign_id], type: 'campaign')[campaign_id][:name]).to eq('Viagem EUA')
      expect(described_class.new(account).resolve([campaign_id], type: 'campaign')[campaign_id][:name]).to eq('Viagem EUA')
      expect(graph).to have_been_requested.once
    end

    [4, 17, 32, 613, 80_004].each do |code|
      it "limite de taxa (#{code}) num lote de 50: uma chamada só, credencial intacta, devolve o que está em cache" do
        cached = '900000000000000001'
        Crm::MetaAdObject.create!(account: account, meta_object_id: cached, object_type: 'campaign', name: 'Em cache', fetched_at: 1.day.ago)
        ids = (1..50).map { |n| (800_000_000_000_000_000 + n).to_s }
        stub_meta_objects(ids: ids, fields: 'name', status: 400, body: meta_graph_error(code, 'User request limit reached'))

        result = resolver.resolve(ids + [cached], type: 'campaign')
        resolver.resolve(ids.first(3), type: 'campaign')

        expect(result.keys).to eq([cached])
        expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).to have_been_made.once
        expect(connection.reload).to have_attributes(status: 'active', last_error: nil)
        expect(Crm::MetaAdObject.where(account_id: account.id, meta_object_id: ids)).to be_empty
      end
    end

    it 'erro 5xx da Meta: uma chamada só, sem refazer ID a ID' do
      ids = [ad_id, '120254710067061111']
      stub_meta_objects(ids: ids, fields: ad_fields, status: 500, body: { error: { message: 'Service temporarily unavailable', code: 2 } })

      expect(resolver.resolve(ids, type: 'ad')).to eq({})
      expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).to have_been_made.once
      expect(connection.reload.status).to eq('active')
    end

    it 'falha de rede não muda a credencial nem lança' do
      stub_request(:get, meta_graph_url).with(query: { ids: ad_id, fields: ad_fields }).to_timeout

      expect(resolver.resolve([ad_id], type: 'ad')).to eq({})
      expect(connection.reload.status).to eq('active')
    end

    it 'token só no header Authorization, nunca na URL' do
      stub_meta_objects(ids: [campaign_id], fields: 'name', body: { campaign_id => { id: campaign_id, name: 'Viagem EUA' } })

      resolver.resolve([campaign_id], type: 'campaign')

      leaked = a_request(:get, meta_graph_url).with(query: hash_including({})) { |request| request.uri.to_s.include?(MetaAdsHelpers::TEST_TOKEN) }
      expect(leaked).not_to have_been_made
      expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).to have_been_made.once
    end
  end

  it 'sem credencial ativa não chama a Graph' do
    create_meta_ads_connection(account, status: 'invalid')

    expect(resolver.resolve(['120254710067060416'], type: 'campaign')).to eq({})
    expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'sem credencial nenhuma não chama a Graph' do
    expect(resolver.resolve(['120254710067060416'], type: 'campaign')).to eq({})
    expect(a_request(:get, meta_graph_url).with(query: hash_including({}))).not_to have_been_made
  end
end
