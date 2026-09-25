require 'rails_helper'

# Porte de lib/services/scoring/score.test.ts do Orth (#681, frente A): fotos, rating e volume híbridos pela coorte,
# atividade pela publishTime da avaliação mais recente. Os pesos "só um sinal" renormalizam para 100, como no Orth.
RSpec.describe Autonomia::Prospecting::Scoring::ComponentScore do
  let(:cohort) { Autonomia::Prospecting::Scoring::Cohort }
  let(:defaults) { Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT }
  let(:reference_time) { Time.utc(2020, 6, 15, 12) }
  let(:photos_only) { defaults.merge('website' => 0, 'phone' => 0, 'rating' => 0, 'volume' => 0, 'activity' => 0) }
  let(:rating_only) { defaults.merge('website' => 0, 'phone' => 0, 'volume' => 0, 'activity' => 0, 'photos' => 0) }
  let(:volume_activity) { defaults.merge('website' => 0, 'phone' => 0, 'rating' => 0, 'photos' => 0) }
  let(:activity_only) { defaults.merge('website' => 0, 'phone' => 0, 'rating' => 0, 'volume' => 0, 'photos' => 0) }
  let(:same_rating_cohort) { cohort.rating([4.0] * 5) }
  let(:context_defaults) { { filters: {}, rating_cohort: cohort::EMPTY_RATING, volume_cohort: cohort::EMPTY_VOLUME } }

  def breakdown(lead, weights: defaults, mode: 'gbp', **context)
    context = described_class::Context.new(mode: mode, weights: weights, reference_time: reference_time, **context_defaults.merge(context))
    described_class.new(Autonomia::Prospecting::Scoring::LeadSignals.from(lead), context).perform
  end

  def published(days_before)
    { 'publishTime' => (reference_time - days_before.days).iso8601, 'relativePublishTimeDescription' => 'ignorado' }
  end

  describe 'fotos no modo GMN (buckets do gradiente)' do
    it 'sem foto vale o peso inteiro e marca sinal fraco' do
      result = breakdown({ photo_count: 0 }, weights: photos_only)

      expect(result.component('photos')['points']).to eq(100)
      expect(result.component('photos')['audit']['reason']).to eq('sem fotos')
      expect(result.confidence_flags).to include('photos')
    end

    it 'segue 0.8, 0.55, 0.35, 0.15 e 0 conforme a quantidade' do
      expectations = { 1 => [0.8, 'quase sem fotos'], 3 => [0.55, 'muito poucas fotos'], 5 => [0.35, 'poucas fotos'],
                       7 => [0.35, 'poucas fotos'], 10 => [0.15, 'fotos suficientes'], 15 => [0, 'muitas fotos'],
                       20 => [0, 'muitas fotos'] }
      expectations.each do |count, (factor, reason)|
        result = breakdown({ photo_count: count }, weights: photos_only)

        expect(result.component('photos')['points']).to be_within(1e-9).of(100 * factor)
        expect(result.component('photos')['audit']['reason']).to eq(reason)
      end
      expect(breakdown({ photo_count: 1 }, weights: photos_only).confidence_flags).not_to include('photos')
    end

    it 'trocar a quantidade de fotos não muda site, telefone, rating e volume' do
      lead = { website: 'https://example.com', phone: '11999' }
      with_none = breakdown(lead.merge(photo_count: 0))
      with_many = breakdown(lead.merge(photo_count: 15))

      %w[website phone rating volume].each do |key|
        expect(with_none.component(key)['points']).to eq(with_many.component(key)['points'])
      end
    end
  end

  describe 'rating híbrido no modo GMN' do
    it 'com menos de 5 notas usa só o absoluto' do
      set = cohort.rating([3.5, 4.0, 4.5])
      expect(set.rated_lead_count).to eq(3)
      expect(set.relative_enabled).to be(false)

      rating = breakdown({ rating: 3.5 }, weights: rating_only, rating_cohort: set).component('rating')

      expect(rating['points']).to be_within(1e-9).of(100 * (5 - 3.5) / 4)
      expect(rating['audit']['rating']['relative_enabled']).to be(false)
      expect(rating['audit']['rating']).not_to have_key('relative_factor')
    end

    it 'com 5 notas e amplitude de 0.2 ou mais mistura 70% absoluto e 30% relativo' do
      set = cohort.rating([3.0, 3.5, 4.0, 4.5, 5.0])
      expect(set.relative_enabled).to be(true)

      rating = breakdown({ rating: 4.0 }, weights: rating_only, rating_cohort: set).component('rating')
      absolute = (5 - 4.0) / 4
      relative = (5 - 4.0) / (5 - 3.0)
      final = (0.7 * absolute) + (0.3 * relative)

      expect(rating['points']).to be_within(1e-9).of(100 * final)
      expect(rating['audit']['rating']['relative_factor']).to be_within(1e-9).of(relative)
      expect(rating['audit']['rating']['final_factor']).to be_within(1e-9).of(final)
    end

    it 'com amplitude menor que 0.2 desliga o relativo mesmo com 5 notas' do
      set = cohort.rating([4.0, 4.05, 4.1, 4.12, 4.15])
      expect(set.r_max - set.r_min).to be < 0.2
      expect(set.relative_enabled).to be(false)

      rating = breakdown({ rating: 4.1 }, weights: rating_only, rating_cohort: set).component('rating')

      expect(rating['points']).to be_within(1e-9).of(100 * (5 - 4.1) / 4)
    end

    it 'sem rating: 1.0 sem avaliações, 0.9 com menos de 5 e 0.75 com 5 ou mais' do
      { nil => 1.0, 0 => 1.0, 3 => 0.9, 10 => 0.75 }.each do |count, factor|
        rating = breakdown({ rating: nil, reviews_count: count }, weights: rating_only,
                                                                  rating_cohort: cohort.rating([nil])).component('rating')

        expect(rating['points']).to be_within(1e-9).of(100 * factor)
        expect(rating['audit']['rating']['final_factor']).to eq(factor)
      end
    end

    it 'o modo Geral ignora a coorte' do
      lead = { rating: 4.2, reviews_count: 10 }
      absurd = cohort::Rating.new(rated_lead_count: 99, r_min: 1, r_max: 5, relative_enabled: true)

      plain = breakdown(lead, weights: rating_only, mode: 'general').component('rating')
      with_cohort = breakdown(lead, weights: rating_only, mode: 'general', rating_cohort: absurd).component('rating')

      expect(plain).to eq(with_cohort)
      expect(plain['points']).to be_within(1e-9).of(80)
    end

    it 'a coorte do conjunto final muda a nota em relação ao conjunto antes do corte' do
      full = cohort.rating([3.0, 3.5, 4.0, 4.5, 5.0])
      final = cohort.rating([3.0, 3.5, 4.0])
      expect(full.relative_enabled).to be(true)
      expect(final.relative_enabled).to be(false)

      right = breakdown({ rating: 3.5 }, weights: rating_only, rating_cohort: final).component('rating')['points']
      wrong = breakdown({ rating: 3.5 }, weights: rating_only, rating_cohort: full).component('rating')['points']

      expect(right).not_to be_within(1e-4).of(wrong)
    end
  end

  describe 'volume híbrido no modo GMN' do
    it 'sem contagem de avaliações usa 0.9 e marca sinal fraco' do
      result = breakdown({ rating: 4.0 }, weights: volume_activity, rating_cohort: same_rating_cohort)
      volume = result.component('volume')

      expect(volume['points']).to be_within(1e-9).of(volume['weight'] * 0.9)
      expect(volume['audit']['weak_signal']).to be(true)
      expect(volume['audit']['volume']['final_factor']).to eq(0.9)
      expect(volume['audit']['volume']['relative_enabled']).to be(false)
      expect(result.confidence_flags).to include('volume')
    end

    it 'zero avaliações é valor válido: absoluto 1 e sem sinal fraco' do
      result = breakdown({ rating: 4.0, reviews_count: 0 }, weights: volume_activity,
                                                            rating_cohort: same_rating_cohort, volume_cohort: cohort.volume([0]))
      volume = result.component('volume')

      expect(volume['audit']['volume']['absolute_factor']).to eq(1)
      expect(volume['audit']['volume']['final_factor']).to eq(1)
      expect(volume['audit']['weak_signal']).to be(false)
      expect(result.confidence_flags).not_to include('volume')
    end

    it 'com menos de 5 contagens usa só o absoluto em escala log' do
      set = cohort.volume([0, 10, 20])
      expect(set.relative_enabled).to be(false)
      expect(set.valid_count_lead_count).to eq(3)

      volume = breakdown({ rating: 4.0, reviews_count: 50 }, weights: volume_activity,
                                                             rating_cohort: same_rating_cohort, volume_cohort: set).component('volume')

      expect(volume['audit']['volume']['relative_enabled']).to be(false)
      expect(volume['audit']['volume']).not_to have_key('relative_factor')
      expect(volume['audit']['volume']['final_factor']).to be_within(1e-9).of(1 - (Math.log(51) / Math.log(201)))
    end

    it 'amplitude log estreita desliga o relativo mesmo com 5 contagens' do
      set = cohort.volume([10] * 5)
      expect(set.valid_count_lead_count).to eq(5)
      expect(set.relative_enabled).to be(false)

      volume = breakdown({ rating: 4.0, reviews_count: 10 }, weights: volume_activity,
                                                             rating_cohort: same_rating_cohort, volume_cohort: set).component('volume')

      expect(volume['audit']['volume']).not_to have_key('relative_factor')
    end

    it 'com 5 contagens e amplitude log de 0.4 ou mais mistura 70% absoluto e 30% relativo' do
      set = cohort.volume([0, 1, 2, 5, 200])
      expect(set.relative_enabled).to be(true)

      volume = breakdown({ rating: 4.0, reviews_count: 10 }, weights: volume_activity,
                                                             rating_cohort: same_rating_cohort, volume_cohort: set).component('volume')
      absolute = 1 - (Math.log(11) / Math.log(201))
      relative = (set.max_log - Math.log(11)) / (set.max_log - set.min_log)

      expect(volume['audit']['volume']['relative_enabled']).to be(true)
      expect(volume['audit']['volume']['final_factor']).to be_within(1e-9).of((0.7 * absolute) + (0.3 * relative))
    end

    it 'o modo Geral ignora a coorte de volume' do
      absurd = cohort::Volume.new(valid_count_lead_count: 99, min_log: 0, max_log: 10, relative_enabled: true)
      weights = defaults.merge('website' => 0, 'phone' => 0, 'rating' => 0, 'activity' => 0, 'photos' => 0)
      lead = { rating: 4.2, reviews_count: 50 }

      expect(breakdown(lead, weights: weights, mode: 'general').component('volume'))
        .to eq(breakdown(lead, weights: weights, mode: 'general', volume_cohort: absurd).component('volume'))
    end

    it 'a atividade não muda quando só a coorte de volume muda' do
      lead = { rating: 4.0, reviews_count: 25 }
      small = breakdown(lead, weights: volume_activity, rating_cohort: same_rating_cohort, volume_cohort: cohort.volume([0, 1]))
      wide = breakdown(lead, weights: volume_activity, rating_cohort: same_rating_cohort,
                             volume_cohort: cohort.volume([0, 1, 2, 3, 500]))

      expect(small.component('activity')).to eq(wide.component('activity'))
    end

    it 'a coorte de volume do conjunto final muda a nota em relação ao conjunto antes do corte' do
      full = [0, 10, 20, 30, 40]
      final = full.first(3)
      expect(cohort.volume(full).relative_enabled).to be(true)
      expect(cohort.volume(final).relative_enabled).to be(false)

      lead = { rating: 4.0, reviews_count: 10 }
      with_full = breakdown(lead, weights: volume_activity, rating_cohort: cohort.rating([4.0] * 5), volume_cohort: cohort.volume(full))
      with_final = breakdown(lead, weights: volume_activity, rating_cohort: cohort.rating([4.0] * 3), volume_cohort: cohort.volume(final))

      expect(with_final.component('volume')['points']).not_to be_within(1e-2).of(with_full.component('volume')['points'])
    end
  end

  describe 'atividade no modo GMN pela avaliação mais recente' do
    it 'segue as faixas de idade em dias' do
      { 0 => 0, 7 => 0, 8 => 0.15, 30 => 0.15, 31 => 0.3, 60 => 0.3, 61 => 0.55, 120 => 0.55, 121 => 0.75, 180 => 0.75,
        181 => 0.9, 365 => 0.9, 366 => 1 }.each do |age, factor|
        expect(described_class.gbp_activity_factor(age)).to eq(factor)
      end
    end

    it 'avaliação de até 7 dias zera a atividade' do
      lead = { rating: 4.0, reviews_count: 50, reviews: [published(3)] }
      result = breakdown(lead, weights: activity_only, rating_cohort: same_rating_cohort)
      activity = result.component('activity')

      expect(activity['audit']['activity']).to include('case' => 'ok', 'final_factor' => 0, 'age_days' => 3)
      expect(activity['points']).to eq(0)
      expect(result.confidence_flags).not_to include('activity')
    end

    it '7 dias vale 0 e 8 dias vale 0.15' do
      seven = breakdown({ reviews: [published(7)] }, weights: activity_only).component('activity')
      eight = breakdown({ reviews: [published(8)] }, weights: activity_only).component('activity')

      expect(seven['audit']['activity']['final_factor']).to eq(0)
      expect(eight['audit']['activity']['final_factor']).to eq(0.15)
    end

    it 'sem avaliações vale 1 e não é sinal fraco' do
      [{ reviews_count: 0 }, { raw_payload: { 'types' => ['establishment'] } }].each do |lead|
        result = breakdown(lead, weights: activity_only)
        activity = result.component('activity')

        expect(activity['audit']['activity']['case']).to eq('no_reviews')
        expect(activity['audit']['activity']['final_factor']).to eq(1)
        expect(activity['audit']['weak_signal']).to be(false)
        expect(result.confidence_flags).not_to include('activity')
      end
    end

    it 'avaliações sem publishTime utilizável valem 0.85 e marcam sinal fraco' do
      result = breakdown({ reviews_count: 5, reviews: [{ 'relativePublishTimeDescription' => 'há 2 dias' }] }, weights: activity_only)
      activity = result.component('activity')

      expect(activity['audit']['activity']['case']).to eq('no_publish_time')
      expect(activity['audit']['activity']['final_factor']).to eq(0.85)
      expect(activity['audit']['weak_signal']).to be(true)
      expect(result.confidence_flags).to include('activity')
    end

    it 'vale a publishTime mais recente entre várias avaliações' do
      activity = breakdown({ reviews: [published(200), published(10)] }, weights: activity_only).component('activity')

      expect(activity['audit']['activity']['age_days']).to eq(10)
      expect(activity['audit']['activity']['final_factor']).to eq(0.15)
    end

    it 'lê as avaliações do raw_payload do Google quando o lead não traz a lista' do
      activity = breakdown({ raw_payload: { 'reviews' => [published(40)] } }, weights: activity_only).component('activity')

      expect(activity['audit']['activity']['age_days']).to eq(40)
    end

    it 'no modo Geral a atividade vem da contagem de avaliações e ignora a publishTime' do
      result = breakdown({ rating: 4.0, reviews_count: 100, reviews: [published(3)] }, weights: activity_only, mode: 'general')
      activity = result.component('activity')

      expect(activity['audit']).not_to have_key('activity')
      expect(activity['audit']['reason']).to eq('negócio muito ativo')
      expect(activity['points']).to eq(result.effective_weights['activity'])
    end

    it 'volume e rating não mudam quando só as avaliações mudam' do
      base = { rating: 3.8, reviews_count: 25 }
      with_reviews = base.merge(reviews: [published(100)])
      volume_cohort = cohort.volume([25, 25])
      rating_cohort = cohort.rating([3.8, 3.8])

      expect(breakdown(base, weights: volume_activity, rating_cohort: rating_cohort, volume_cohort: volume_cohort).component('volume'))
        .to eq(breakdown(with_reviews, weights: volume_activity, rating_cohort: rating_cohort, volume_cohort: volume_cohort).component('volume'))
      expect(breakdown(base, weights: rating_only, rating_cohort: rating_cohort).component('rating'))
        .to eq(breakdown(with_reviews, weights: rating_only, rating_cohort: rating_cohort).component('rating'))
    end

    it 'o filtro de mínimo de 50 avaliações zera o volume mas não a atividade' do
      result = breakdown({ rating: 4.0, reviews_count: 100 }, filters: { 'reviews_min' => '50' },
                                                              rating_cohort: cohort.rating([4.0]), volume_cohort: cohort.volume([100]))

      expect(result.effective_weights['volume']).to eq(0)
      expect(result.effective_weights['activity']).to be > 0
      expect(result.component('activity')['audit']['activity']).to include('case' => 'no_reviews', 'final_factor' => 1)
    end
  end

  describe 'leitura invertida por modo' do
    let(:complete) { { website: 'https://a.com', phone: '11 9999', rating: 4.8, reviews_count: 150, photo_count: 20, reviews: [published(2)] } }
    let(:empty) { { website: nil, phone: nil, rating: nil, reviews_count: nil, photo_count: 0 } }

    it 'no GMN o perfil completo tem nota baixa e o vazio tem nota alta' do
      expect(breakdown(complete).total).to be < 15
      expect(breakdown(empty).total).to be > 90
    end

    it 'no Geral o perfil completo tem nota alta e o vazio tem nota baixa' do
      expect(breakdown(complete, mode: 'general').total).to eq(100)
      expect(breakdown(empty, mode: 'general').total).to eq(0)
    end

    it 'site e telefone presentes pontuam só no Geral' do
      lead = { website: 'https://a.com', phone: '11 9999' }

      expect(breakdown(lead).component('website')['points']).to eq(0)
      expect(breakdown(lead, mode: 'general').component('website')['points']).to eq(30)
      expect(breakdown(lead).component('phone')['points']).to eq(0)
      expect(breakdown(lead, mode: 'general').component('phone')['points']).to eq(10)
    end
  end

  describe 'multiplicador de tração pela posição no Google' do
    it 'vale só no GMN, com faixas de 1.5 a 0.7' do
      { nil => 1.0, 1 => 1.5, 5 => 1.5, 6 => 1.3, 10 => 1.3, 11 => 1.1, 20 => 1.1, 21 => 0.9, 40 => 0.9, 41 => 0.7 }.each do |rank, factor|
        expect(breakdown({ search_rank: rank }).traction_multiplier).to eq(factor)
        expect(breakdown({ search_rank: rank }, mode: 'general').traction_multiplier).to eq(1.0)
      end
    end

    it 'multiplica a soma e limita a nota em 100' do
      lead = { website: nil, phone: nil, rating: 4.0, reviews_count: 100, photo_count: 20 }
      plain = breakdown(lead)
      top = breakdown(lead.merge(search_rank: 3))

      expect(top.total).to eq([(plain.components.sum { |item| item['points'] } * 1.5).round, 100].min)
      expect(breakdown({ search_rank: 1 }).total).to eq(100)
    end
  end
end
