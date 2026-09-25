require 'rails_helper'

# Modo sombra e virada por conta da nota do Orth (#681, frente B). Toda busca nova calcula as duas notas; a conta vê a
# do motor que o superadmin escolheu, e a outra fica gravada na busca para comparar.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }
  let(:orth_scorer) { Autonomia::Prospecting::Scoring::OrthScorer }
  let(:weight_mapping) { Autonomia::Prospecting::Scoring::WeightMapping }
  let(:mock_provider_class) { Autonomia::Prospecting::Providers::MockProvider }
  let(:places) do
    [
      { provider: 'mock', provider_place_id: 'places/a', name: 'Alfa Odonto', phone: '+5541999990001', website: 'https://alfa.example.com',
        rating: 4.8, reviews_count: 120, raw_payload: { 'photos' => [{}, {}] }, open_now: true },
      { provider: 'mock', provider_place_id: 'places/b', name: 'Beta Odonto', phone: nil, website: nil,
        rating: 3.9, reviews_count: 5, raw_payload: {}, open_now: false },
      { provider: 'mock', provider_place_id: 'places/c', name: 'Gama Odonto', phone: '+5541999990003', website: 'https://gama.example.com',
        rating: nil, reviews_count: 40, raw_payload: {}, open_now: true }
    ]
  end
  # Nota do Orth por lugar, na ordem do Google: invertida em relação à legada, para a virada mexer na ordem.
  let(:orth_by_name) do
    {
      'Alfa Odonto' => { score: 12, priority_score: 5, insight: 'Oportunidade baixa' },
      'Beta Odonto' => { score: 91, priority_score: 100, insight: 'Oportunidade alta: sem site.' },
      'Gama Odonto' => { score: 55, priority_score: 60, insight: 'Oportunidade média' }
    }
  end
  let(:orth_calls) { [] }

  before do
    setting.update!(provider: 'mock', cache_ttl_seconds: 0)
    allow(mock_provider_class).to receive(:new).and_return(instance_double(mock_provider_class, search: places))
    allow(orth_scorer).to receive(:new) do |**arguments|
      orth_calls << arguments
      instance_double(orth_scorer, perform: arguments[:leads].map { |lead| orth_result(orth_by_name.fetch(lead[:name])) })
    end
  end

  def orth_result(values)
    orth_scorer::Result.new(
      score: values[:score], priority_score: values[:priority_score], human_insight: values[:insight],
      components: [{ key: 'website', weight: 30, value: 1.0, points: 30, audit: 'sem site' }],
      negative_factors: ['no_website'], effective_weights: { 'website' => 30, 'phone' => 10 },
      priority_position: nil, negative_penalty: 0, confidence_flags: [], traction_multiplier: 1.0, priority_factors: {}
    )
  end

  def run_search(params = {})
    described_class.new(account: account, user: user,
                        params: { query: 'dentista', location: 'Curitiba, PR', requested_limit: 3 }.merge(params)).perform
  end

  def scoring_by_name(result)
    result.leads.to_h { |lead| [lead.name, result.search.metadata['lead_scoring'][lead.id.to_s]] }
  end

  describe 'motor legado (padrão)' do
    it 'grava a nota do Orth em sombra, com faixa e frase, sem mexer no que a conta vê' do
      result = run_search
      scoring = scoring_by_name(result)

      expect(setting.reload.score_engine).to eq('legacy')
      expect(scoring['Beta Odonto']['orth']).to eq(
        'score' => 91, 'priority_score' => 100, 'band' => 'very_hot', 'human_insight' => 'Oportunidade alta: sem site.'
      )
      expect(scoring.transform_values { |item| item['orth']['band'] })
        .to eq('Alfa Odonto' => 'low', 'Beta Odonto' => 'very_hot', 'Gama Odonto' => 'high')
      result.leads.each do |lead|
        lead.reload
        expect(lead.score_breakdown['_mode']).to eq('gbp')
        expect(lead.score_breakdown).not_to have_key('_engine')
        expect(lead.human_insight).not_to eq(orth_by_name[lead.name][:insight])
        expect(scoring[lead.name].except('orth')).to eq(
          'score' => lead.score.to_f, 'score_breakdown' => lead.score_breakdown,
          'priority_score' => lead.priority_score.to_f, 'priority_position' => lead.priority_position
        )
      end
    end

    it 'mantém a ordem de prioridade legada' do
      legacy_order = run_search.leads.sort_by(&:priority_position).map(&:name)
      allow(orth_scorer).to receive(:new).and_raise(RuntimeError, 'fórmula fora do ar')

      expect(run_search.leads.sort_by(&:priority_position).map(&:name)).to eq(legacy_order)
    end

    it 'termina a busca quando a nota do Orth falha, registra o erro e não grava sombra' do
      allow(orth_scorer).to receive(:new).and_raise(RuntimeError, 'fórmula fora do ar')
      allow(Rails.logger).to receive(:warn)

      result = run_search

      expect(result.search).to be_completed
      expect(result.search.metadata['score_shadow_error']).to eq('RuntimeError')
      expect(result.search.metadata['lead_scoring'].values).to all(satisfy { |item| !item.key?('orth') })
      expect(Rails.logger).to have_received(:warn).with(/score_shadow_failed account_id=#{account.id} error=RuntimeError/)
    end
  end

  describe 'motor do Orth (conta virada)' do
    before { setting.update!(score_engine: 'orth') }

    it 'mostra a nota, a prioridade, a ordem, a faixa e a frase do Orth, e guarda a legada para comparar' do
      result = run_search
      leads = result.leads.map(&:reload).sort_by(&:priority_position)
      scoring = scoring_by_name(result)

      expect(leads.map(&:name)).to eq(['Beta Odonto', 'Gama Odonto', 'Alfa Odonto'])
      expect(leads.map { |lead| [lead.score.to_f, lead.priority_score.to_f] }).to eq([[91.0, 100.0], [55.0, 60.0], [12.0, 5.0]])
      expect(leads.first.human_insight).to eq('Oportunidade alta: sem site.')
      expect(leads.first.negative_factors).to eq(['no_website'])
      expect(scoring['Beta Odonto']).to include('score' => 91.0, 'priority_score' => 100.0, 'priority_position' => 1)
      expect(scoring['Beta Odonto']['orth']).to include('band' => 'very_hot')
      expect(scoring['Beta Odonto']['legacy'].keys).to match_array(%w[score priority_score priority_position band human_insight])
    end

    it 'grava o detalhe da nota do Orth no formato que a tela já lê, marcado com o motor' do
      breakdown = run_search.leads.map(&:reload).min_by(&:priority_position).score_breakdown

      expect(breakdown).to include('_engine' => 'orth', '_mode' => 'gbp', '_total' => 91,
                                   '_effective_weights' => { 'website' => 30, 'phone' => 10 })
      expect(breakdown['website']).to eq('signal' => 1.0, 'weight' => 30, 'weighted_score' => 30, 'audit' => 'sem site')
    end

    it 'guarda na busca a nota legada que a conta via antes da virada' do
      setting.update!(score_engine: 'legacy')
      legacy = run_search.leads.to_h { |lead| [lead.name, [lead.score.to_f, lead.priority_position]] }
      setting.update!(score_engine: 'orth')

      stored = scoring_by_name(run_search).transform_values { |item| item['legacy'].values_at('score', 'priority_position') }

      expect(stored).to eq(legacy)
    end

    it 'desliga o motor do Orth quando a nota falha: a busca falha em vez de mostrar a legada como se fosse a do Orth' do
      allow(orth_scorer).to receive(:new).and_raise(RuntimeError, 'fórmula fora do ar')

      expect { run_search }.to raise_error(described_class::ScoreEngineError, 'RuntimeError: fórmula fora do ar')
      expect(Autonomia::Prospecting::Search.last).to be_failed
      expect(Autonomia::Prospecting::Lead.count).to eq(0)
    end

    it 'não serve do cache uma busca calculada no motor legado' do
      setting.update!(score_engine: 'legacy', cache_ttl_seconds: 3600)
      run_search
      setting.update!(score_engine: 'orth')

      expect(run_search.search.metadata['cached_from_search_id']).to be_nil
    end
  end

  describe 'busca antiga' do
    it 'não é reescrita quando a conta vira nem quando uma busca nova regrava os mesmos leads' do
      old_search = run_search.search
      old_metadata = old_search.reload.metadata.deep_dup
      setting.update!(score_engine: 'orth')

      run_search

      expect(old_search.reload.metadata).to eq(old_metadata)
    end
  end

  describe 'pesos passados à nota do Orth' do
    it 'usa o padrão do Orth quando a conta está no perfil padrão' do
      run_search(metadata: { advanced_filters: { has_website: 'yes', open_now: 'yes' }, score_mode: 'general' })

      expect(orth_calls.last).to include(weights: nil, mode: 'general')
      expect(orth_calls.last[:filters]).to eq('has_website' => 'yes', 'open_now' => 'yes')
    end

    it 'mapeia os pesos próprios da conta para os componentes do Orth' do
      custom = { 'website' => 40, 'phone' => 10, 'rating' => 10, 'reviews_count' => 10, 'activity' => 10, 'photos' => 10,
                 'google_rank' => 5, 'query_relevance' => 5 }
      setting.update!(scoring_mode: 'custom', custom_scoring_weights: custom)
      allow(weight_mapping).to receive(:from_legacy).with(custom).and_return('website' => 45)

      run_search

      expect(orth_calls.last[:weights]).to eq('website' => 45)
    end

    it 'mapeia os pesos de um perfil do catálogo que não é o padrão' do
      profile = Autonomia::Prospecting::ScoringProfile.create!(name: 'Vender site', weights: { 'website' => 60 })
      setting.update!(scoring_mode: 'profile', scoring_profile: profile)
      allow(weight_mapping).to receive(:from_legacy).with(profile.weights_with_defaults).and_return('website' => 70)

      run_search

      expect(orth_calls.last[:weights]).to eq('website' => 70)
    end

    it 'passa ao Orth o lead com os sinais que ele lê, na ordem do Google' do
      run_search

      first = orth_calls.last[:leads].first
      expect(orth_calls.last[:leads].pluck(:name)).to eq(['Alfa Odonto', 'Beta Odonto', 'Gama Odonto'])
      expect(first).to include(website: 'https://alfa.example.com', phone: '+5541999990001', rating: 4.8, reviews_count: 120,
                               search_rank: 1, open_now: true, whatsapp_verified: false, decisor_found: false, decisor_failed: false)
    end

    # Penalidade "já no CRM" do Orth (negative-factors.ts): o lead que a busca reencontra já virou card.
    it 'marca como já no CRM, com o nome do funil, o lead que já tem card' do
      run_search
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Alfa Odonto')
      Autonomia::Prospecting::Lead.find_by!(account: account, name: 'Alfa Odonto').update!(crm_card: card)

      run_search

      leads = orth_calls.last[:leads].index_by { |lead| lead[:name] }
      expect(leads['Alfa Odonto']).to include(already_in_crm: true, crm_funnel_name: 'Funil Comercial')
      expect(leads['Beta Odonto']).to include(already_in_crm: false, crm_funnel_name: nil)
    end
  end
end
