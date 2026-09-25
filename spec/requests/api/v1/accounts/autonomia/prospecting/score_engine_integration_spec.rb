require 'rails_helper'

# Integração das três frentes do #681, sem dublê: a busca passa pelo provider do Google (só a resposta HTTP é simulada,
# com o fixture real), pela nota legada, pela fórmula do Orth, pela gravação da sombra e pelo relatório de comparação.
# A mesma busca roda numa conta ainda no motor legado e noutra virada para o Orth.
RSpec.describe 'Autonomia prospecting score engine integration', type: :request do
  include_context 'with prospecting legacy engine snapshot'
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:band) { Autonomia::Prospecting::Scoring::Band }
  let(:google_fixture) { JSON.parse(file_fixture('google_places/search_text_filtros.json').read) }
  let(:legacy_account) { create(:account) }
  let(:orth_account) { create(:account) }

  before do
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: google_fixture.merge('places' => ProspectingPayloadSnapshot.places(google_fixture)).to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def prepare(account, engine)
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0, score_engine: engine)
    account
  end

  def search(account)
    admin = create(:user, :administrator, account: account)
    travel_to(ProspectingPayloadSnapshot::FROZEN_AT) do
      post "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches",
           params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 8, metadata: { score_mode: 'gbp' } } },
           headers: auth_headers(admin), as: :json
    end
    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    [payload['leads'].index_by { |lead| lead['name'] }, Autonomia::Prospecting::Search.find(payload.dig('search', 'id'))]
  end

  def scoring_by_name(search_record)
    names = search_record.leads.pluck(:id, :name).to_h
    search_record.metadata['lead_scoring'].transform_keys { |lead_id| names.fetch(lead_id.to_i) }
  end

  describe 'conta no motor legado' do
    it 'devolve o payload de antes, byte a byte, com a fórmula do Orth de verdade rodando em sombra', :aggregate_failures do
      expect("#{JSON.pretty_generate(legacy_engine_snapshot)}\n").to eq(file_fixture(ProspectingPayloadSnapshot::FIXTURE).read)

      searches = Autonomia::Prospecting::Search.where(account: snapshot_account)
      expect(searches.count).to eq(2)
      searches.each do |search_record|
        expect(search_record.metadata).not_to have_key('score_shadow_error')
        search_record.metadata['lead_scoring'].each_value do |scoring|
          expect(scoring).not_to have_key('legacy')
          expect(scoring['orth'].keys).to match_array(%w[score priority_score band human_insight])
          expect(scoring['orth']['score']).to be_an(Integer).and(be_between(0, 100))
          expect(scoring['orth']['band']).to eq(band.code(scoring['orth']['priority_score']))
          expect(scoring['orth']['human_insight']).to be_present
        end
      end
    end
  end

  describe 'conta virada para o Orth' do
    it 'mostra a nota, a prioridade, a ordem e a frase do Orth, iguais à sombra da conta legada, e guarda a legada', :aggregate_failures do
      legacy_leads, legacy_search = search(prepare(legacy_account, 'legacy'))
      orth_leads, orth_search = search(prepare(orth_account, 'orth'))
      shadow = scoring_by_name(legacy_search)
      stored = scoring_by_name(orth_search)

      expect(orth_leads.keys).to match_array(legacy_leads.keys)
      orth_leads.each do |name, lead|
        expect(lead['score'].to_f).to eq(shadow[name]['orth']['score'].to_f)
        expect(lead['priority_score'].to_f).to eq(shadow[name]['orth']['priority_score'].to_f)
        expect(lead['human_insight']).to eq(shadow[name]['orth']['human_insight'])
        expect(lead['score_breakdown']).to include('_engine' => 'orth', '_mode' => 'gbp')
        expect(band.code(lead['priority_score'])).to eq(stored[name]['orth']['band'])
        expect(stored[name]['legacy'].slice('score', 'priority_score', 'priority_position'))
          .to eq(legacy_leads[name].slice('score', 'priority_score', 'priority_position').transform_values { |v| v.is_a?(String) ? v.to_f : v })
      end

      by_position = orth_leads.values.sort_by { |lead| lead['priority_position'] }
      expect(by_position.map { |lead| lead['priority_score'].to_f }).to eq(by_position.map { |lead| lead['priority_score'].to_f }.sort.reverse)
      # A fórmula precisa mexer em alguém; se não mexer, a comparação acima não prova nada.
      expect(orth_leads.any? { |name, lead| (lead['priority_score'].to_f - legacy_leads[name]['priority_score'].to_f).nonzero? }).to be(true)
    end
  end

  describe 'relatório de comparação' do
    it 'conta quem sobe, desce e fica igual pela prioridade que a tela mostrou em cada motor', :aggregate_failures do
      legacy_leads, = search(prepare(legacy_account, 'legacy'))
      orth_leads, = search(prepare(orth_account, 'orth'))
      deltas = legacy_leads.to_h { |name, lead| [name, orth_leads.fetch(name)['priority_score'].to_f - lead['priority_score'].to_f] }
      expected = { sobem: deltas.values.count(&:positive?), descem: deltas.values.count(&:negative?), iguais: deltas.values.count(&:zero?) }
      expect(expected[:sobem] + expected[:descem]).to be_positive

      [legacy_account, orth_account].each do |account|
        report = Autonomia::Prospecting::Scoring::ShadowReport.new(account: account, since: 1.year.ago).perform

        expect(report.slice(:buscas, :buscas_sem_sombra, :leads)).to eq(buscas: 1, buscas_sem_sombra: 0, leads: legacy_leads.size)
        expect(report.slice(:sobem, :descem, :iguais)).to eq(expected)
        top = report[:top10].first
        expect(deltas.fetch(top[:nome]).abs).to eq(deltas.values.map(&:abs).max)
        expect(top.slice(:legacy, :orth)).to eq(legacy: legacy_leads.fetch(top[:nome])['priority_score'].to_f.round,
                                                orth: orth_leads.fetch(top[:nome])['priority_score'].to_f.round)
        expect(top[:faixa_orth]).to eq(band.label(band.code(orth_leads.fetch(top[:nome])['priority_score'])))
      end
    end
  end
end
