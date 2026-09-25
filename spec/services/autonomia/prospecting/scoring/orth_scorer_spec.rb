require 'rails_helper'

# Contrato da frente A (#681): recebe os leads de uma busca, devolve um Result por lead na mesma ordem. A coorte do
# rating e do volume é o próprio conjunto passado; os filtros da busca mexem nos pesos e no bônus de aberto agora.
RSpec.describe Autonomia::Prospecting::Scoring::OrthScorer do
  let(:reference_time) { Time.utc(2026, 9, 25, 12) }
  let(:defaults) { Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT }
  let(:complete) do
    { website: 'https://a.com', phone: '11 9999', rating: 4.8, reviews_count: 150, photo_count: 20,
      reviews: [{ 'publishTime' => (reference_time - 2.days).iso8601 }] }
  end
  let(:empty) { { website: nil, phone: '11 8888', rating: nil, reviews_count: nil, photo_count: 0 } }

  def perform(leads, mode: 'gbp', weights: nil, filters: {})
    described_class.new(leads: leads, mode: mode, weights: weights, filters: filters, reference_time: reference_time).perform
  end

  it 'devolve um resultado por lead, na mesma ordem' do
    results = perform([complete, empty])

    expect(results.size).to eq(2)
    expect(results).to all(be_a(described_class::Result))
    expect(results.first.score).to be < results.last.score
  end

  it 'cada resultado traz nota e prioridade inteiras, componentes, penalidades, frase e pesos' do
    perform([complete, empty]).each do |result|
      expect([result.score, result.priority_score]).to all(be_an(Integer).and(be_between(0, 100)))
      expect(result.components.pluck('key')).to eq(%w[website phone rating volume activity photos])
      expect(result.components.first.keys).to eq(%w[key weight value points audit])
      expect(result.negative_factors).to be_an(Array)
      expect(result.human_insight).to be_present
      expect(result.effective_weights.keys).to eq(defaults.keys)
    end
  end

  it 'sem leads devolve vazio' do
    expect(perform([])).to eq([])
  end

  it 'aceita lead com chave em texto' do
    expect(perform([complete.stringify_keys]).first.score).to eq(perform([complete]).first.score)
  end

  it 'pesos nil usam o padrão do Orth' do
    expect(perform([complete]).first.effective_weights).to eq(defaults)
  end

  it 'usa os pesos passados' do
    weights = { 'website' => 100, 'phone' => 0, 'rating' => 0, 'volume' => 0, 'activity' => 0, 'photos' => 0 }

    expect(perform([empty], weights: weights).first.score).to eq(100)
    expect(perform([complete], weights: weights).first.score).to eq(0)
  end

  it 'recusa modo desconhecido' do
    expect { perform([complete], mode: 'outro') }.to raise_error(ArgumentError)
  end

  describe 'leitura invertida por modo' do
    it 'no GMN o perfil vazio vem na frente; no Geral o completo' do
      gbp = perform([complete, empty])
      general = perform([complete, empty], mode: 'general')

      expect(gbp.map(&:score)).to eq([2, 89])
      expect(general.map(&:score)).to eq([100, 10])
      expect(gbp.first.human_insight).to start_with('Oportunidade baixa')
      expect(general.first.human_insight).to start_with('Lead bem qualificado')
    end
  end

  describe 'coorte' do
    let(:cohort) { [3.0, 3.5, 4.0, 4.5, 5.0].map { |rating| { rating: rating, reviews_count: 10, photo_count: 20 } } }

    it 'é o conjunto passado: com 5 notas espalhadas o rating mistura o relativo' do
      rating = perform(cohort).third.components.find { |item| item['key'] == 'rating' }

      expect(rating['audit']['rating']['relative_enabled']).to be(true)
      expect(rating['value']).to be_within(1e-9).of((0.7 * 0.25) + (0.3 * 0.5))
    end

    it 'o mesmo lead sozinho usa só o absoluto' do
      rating = perform([cohort.third]).first.components.find { |item| item['key'] == 'rating' }

      expect(rating['audit']['rating']['relative_enabled']).to be(false)
      expect(rating['value']).to be_within(1e-9).of(0.25)
    end

    it 'o volume também sai da coorte do conjunto' do
      leads = [0, 1, 2, 5, 200].map { |count| { rating: 4.0, reviews_count: count } }
      volume = perform(leads).fourth.components.find { |item| item['key'] == 'volume' }

      expect(volume['audit']['volume']['relative_enabled']).to be(true)
      expect(perform([leads.fourth]).first.components.find { |item| item['key'] == 'volume' }['audit']['volume']['relative_enabled'])
        .to be(false)
    end
  end

  describe 'filtros' do
    it 'filtro de site zera o peso do site e renormaliza os outros para 100' do
      result = perform([empty], filters: { 'has_website' => 'no' }).first

      expect(result.effective_weights).to eq('website' => 0, 'phone' => 14, 'rating' => 30, 'volume' => 21, 'activity' => 14, 'photos' => 21)
      expect(result.score).to eq(84)
      expect(perform([empty]).first.score).to eq(89)
    end

    it 'o sinal zerado pelo filtro sai da frase' do
      expect(perform([empty], filters: { 'has_website' => 'no' }).first.human_insight).not_to include('site')
      expect(perform([empty]).first.human_insight).to include('sem site')
    end

    it 'aberto agora ganha bônus de prioridade só sem o filtro de aberto agora' do
      open_now = empty.merge(open_now: true)

      expect(perform([open_now]).first.priority_factors[:hour]).to eq(1.15)
      expect(perform([open_now], filters: { 'open_now' => 'yes' }).first.priority_factors[:hour]).to eq(1.0)
    end
  end

  describe 'prioridade' do
    it 'normaliza por percentil e dá a posição na busca' do
      results = perform([complete, empty, empty.merge(phone: nil)])

      expect(results.map(&:priority_score)).to eq([0, 100, 50])
      expect(results.map(&:priority_position)).to eq([3, 1, 2])
    end

    it 'penalidade desce o lead e vira código em negative_factors' do
      results = perform([empty.merge(already_in_crm: true), empty])

      expect(results.first.negative_factors).to eq(['already_in_crm'])
      expect(results.first.negative_penalty).to eq(40)
      expect(results.map(&:priority_position)).to eq([2, 1])
      expect(results.map(&:score).uniq.size).to eq(1)
    end
  end

  it 'a posição no Google multiplica a nota no GMN' do
    expect(perform([complete.merge(search_rank: 50)]).first.traction_multiplier).to eq(0.7)
    expect(perform([complete.merge(search_rank: 50)], mode: 'general').first.traction_multiplier).to eq(1.0)
  end
end
