# As regras do consultor de anúncios (#1110, F5, §1.3): cada uma olha os fatos e diz pass, fail, no_data ou
# not_applicable, com a evidência e o limiar que usou. Quem decide a ação é a Decision; quem escreve é a IA.
#
# Pequeno negócio tem pouco dado: uma regra sem amostra suficiente diz `no_data` em vez de arriscar. O CTR só vale
# com mil impressões nas duas janelas e 30 cliques na linha de base (mil impressões a 1,5% são 15 cliques: uma
# queda de 20% seria ruído). Regra de várias partes (`fatigue`, `scale`) combina assim: qualquer fail → fail;
# senão qualquer no_data → no_data; senão pass.
#
# Mudou limiar, regra ou o gabarito (spec/services/crm/meta_ads/advisor/scenarios_spec.rb)? Sobe RULES_VERSION e
# explica no PR: a versão entra na chave do cache dos fatos e na assinatura do run.
module Crm::MetaAds::Advisor::Rules
  RULES_VERSION = 'f5.2'.freeze
  MIN_IMPRESSIONS = 1_000
  MIN_BASELINE_CLICKS = 30
  FATIGUE_CTR_DROP = 0.20
  FATIGUE_FREQUENCY = 4.0
  AUCTION_CPM_RISE = 0.30
  STABLE_CTR = 0.10
  SCALE_FREQUENCY = 3.0
  SCALE_STEP = 0.20
  SCALE_COOLDOWN_DAYS = 5
  SCALE_WEEKS = 2
  LEARNING_RESULTS = 50
  DATA_GATE_FACTOR = 3
  SLOW_RESPONSE = 300
  MIN_RESPONSES = 10
  MAX_UNANSWERED_SHARE = 0.20
  WINDOW_DAYS = 7
  ACCOUNT_RULES = %w[stalled_quotes slow_response tracking auction].freeze
  AD_RULES = %w[data_gate learning fatigue scale].freeze

  module_function

  # → [{ key:, scope:, ad_id:, status:, evidence:, threshold: }]: as 4 de conta e as 4 de cada anúncio.
  def evaluate(facts, history:)
    facts = facts.deep_symbolize_keys
    account = facts[:account]
    accepted = Array(history[:scale_accepted_ad_ids]).map(&:to_s)
    [stalled_quotes(account), slow_response(account), tracking(account), auction(account)] +
      facts[:ads].flat_map { |row| ad_rules(row, account, accepted) }
  end

  def result(key, status, evidence: {}, threshold: {}, ad_id: nil)
    { key: key, scope: ad_id ? 'ad' : 'account', ad_id: ad_id, status: status, evidence: evidence, threshold: threshold }
  end

  def stalled_quotes(account)
    stalled = account[:stalled]
    status = if account[:open_quotes].zero? then 'not_applicable'
             else
               stalled[:count].positive? ? 'fail' : 'pass'
             end
    result('stalled_quotes', status, evidence: { open_quotes: account[:open_quotes], count: stalled[:count], value: stalled[:value] },
                                     threshold: { days: stalled[:days] })
  end

  def slow_response(account)
    response = account[:response]
    total = response[:answered] + response[:unanswered]
    share = total.zero? ? nil : response[:unanswered].fdiv(total)
    result('slow_response', slow_status(account, total, share), evidence: response.merge(unanswered_share: share),
                                                                threshold: { median_seconds: SLOW_RESPONSE, unanswered_share: MAX_UNANSWERED_SHARE,
                                                                             min_responses: MIN_RESPONSES })
  end

  def slow_status(account, total, share)
    return 'not_applicable' if account[:conversations_30d].zero?
    return 'no_data' if total < MIN_RESPONSES

    account[:response][:median_seconds].to_i > SLOW_RESPONSE || share >= MAX_UNANSWERED_SHARE ? 'fail' : 'pass'
  end

  # A mesma conta da F3 (Panel::Action.tracking_payload): menos de 70% com anúncio identificado.
  def tracking(account)
    confidence = account[:confidence]
    status = if confidence[:conversations].to_i < Crm::MetaAds::Panel::Action::MIN_SAMPLE then 'no_data'
             else
               Crm::MetaAds::Panel::Action.tracking_payload(confidence) ? 'fail' : 'pass'
             end
    result('tracking', status, evidence: confidence.merge(identified: confidence[:ad].to_i + confidence[:ad_name].to_i),
                               threshold: { identified_pct: Crm::MetaAds::Panel::Action::MIN_CONFIDENT })
  end

  # CPM subindo com o CTR parado é a concorrência; CPM subindo com o CTR caindo é fadiga (outra regra).
  def auction(account)
    cpm_change = change(account[:cpm_recent], account[:cpm_baseline])
    ctr_change = change(account[:ctr_recent], account[:ctr_baseline])
    result('auction', auction_status(account, cpm_change, ctr_change),
           evidence: account.slice(:cpm_recent, :cpm_baseline, :ctr_recent, :ctr_baseline).merge(cpm_change_pct: cpm_change,
                                                                                                 ctr_change_pct: ctr_change),
           threshold: { cpm_change_pct: AUCTION_CPM_RISE, ctr_change_pct: STABLE_CTR })
  end

  def auction_status(account, cpm_change, ctr_change)
    return 'not_applicable' if account[:spend_recent].to_f.zero?
    return 'no_data' if !ctr_measurable?(account) || cpm_change.nil?

    cpm_change >= AUCTION_CPM_RISE && ctr_change.abs < STABLE_CTR ? 'fail' : 'pass'
  end

  def ad_rules(row, account, accepted)
    gate = data_gate(row, account)
    learn = learning(row)
    [gate, learn, fatigue(row), scale(row, account, { data_gate: gate[:status], learning: learn[:status] }, accepted)]
  end

  def data_gate(row, account)
    result('data_gate', gate_status(row, account[:target_cost_per_sale]), ad_id: row[:ad_id],
                                                                          evidence: target_evidence(row, account).merge(spend_30d: row[:spend_30d]),
                                                                          threshold: { factor: DATA_GATE_FACTOR })
  end

  def gate_status(row, target)
    return 'not_applicable' if row[:spend_30d].to_f.zero?
    return 'no_data' if target.nil?

    row[:spend_30d] < DATA_GATE_FACTOR * target ? 'fail' : 'pass'
  end

  # Aproximação do aprendizado da Meta pelo conjunto (D5.5): sem conversa contada pela Meta, não dá para saber.
  def learning(row)
    results = row[:adset_meta_results_7d].to_i
    status = if row[:adset_spend_recent].to_f.zero? then 'not_applicable'
             elsif row[:adset_id].nil? || results.zero? then 'no_data'
             else
               results < LEARNING_RESULTS ? 'fail' : 'pass'
             end
    result('learning', status, ad_id: row[:ad_id], evidence: { adset_id: row[:adset_id], adset_meta_results_7d: results },
                               threshold: { results: LEARNING_RESULTS })
  end

  def fatigue(row)
    drop = ctr_measurable?(row) ? -change(row[:ctr_recent], row[:ctr_baseline]) : nil
    parts = { ctr: part(drop.nil?, drop.to_f >= FATIGUE_CTR_DROP),
              frequency: part(row[:frequency_7d].nil?, row[:frequency_7d].to_f > FATIGUE_FREQUENCY) }
    status = row[:spend_recent].to_f.zero? ? 'not_applicable' : combine(parts.values)
    result('fatigue', status, ad_id: row[:ad_id],
                              evidence: { trigger: trigger(parts), ctr_drop_pct: drop, frequency_7d: row[:frequency_7d],
                                          frequency_date_end: row[:frequency_date_end] }.merge(parts),
                              threshold: { ctr_drop_pct: FATIGUE_CTR_DROP, frequency_7d: FATIGUE_FREQUENCY })
  end

  # A única regra que dispara em pass: tudo precisa estar certo para aumentar o orçamento.
  def scale(row, account, gates, accepted)
    parts = gates.merge(
      week_a: week_part(row[:week_a], account), week_b: week_part(row[:week_b], account),
      frequency: part(row[:frequency_7d].nil?, row[:frequency_7d].to_f >= SCALE_FREQUENCY),
      cooldown: accepted.include?(row[:ad_id].to_s) ? 'fail' : 'pass'
    )
    status = row[:verdict] == 'up' ? combine(parts.values) : 'not_applicable'
    result('scale', status, ad_id: row[:ad_id], evidence: target_evidence(row, account).merge(parts),
                            threshold: { frequency_7d: SCALE_FREQUENCY, step: SCALE_STEP, cooldown_days: SCALE_COOLDOWN_DAYS, weeks: SCALE_WEEKS })
  end

  def week_part(week, account)
    return 'no_data' if week[:spend].to_f.zero?
    return 'fail' if week[:sales].zero? || account[:target_cost_per_sale].nil? || week[:cost_per_sale] > account[:target_cost_per_sale]

    'pass'
  end

  # D5.3: o custo-alvo é a média dos anúncios que venderam; com um só vendendo, ele é a própria média.
  def target_evidence(row, account)
    { target_cost_per_sale: account[:target_cost_per_sale], selling_ads: account[:selling_ads], target_includes_ad: row[:sales].to_i.positive? }
  end

  def ctr_measurable?(facts)
    facts[:impressions_recent].to_i >= MIN_IMPRESSIONS && facts[:impressions_baseline].to_i >= MIN_IMPRESSIONS &&
      facts[:link_clicks_baseline].to_i >= MIN_BASELINE_CLICKS
  end

  # Fração com sinal; nil sem base.
  def change(recent, baseline)
    return if recent.nil? || baseline.nil? || baseline.zero?

    (recent - baseline) / baseline
  end

  def part(missing, failed)
    return 'no_data' if missing

    failed ? 'fail' : 'pass'
  end

  # Parte `not_applicable` (anúncio `up` sem gasto no período, por exemplo) não basta para escalar: conta como no_data.
  def combine(statuses)
    return 'fail' if statuses.include?('fail')
    return 'no_data' if statuses.any? { |status| %w[no_data not_applicable].include?(status) }

    'pass'
  end

  def trigger(parts)
    return 'both' if parts.values.all?('fail')
    return 'ctr' if parts[:ctr] == 'fail'

    'frequency' if parts[:frequency] == 'fail'
  end
end
