# O que fazer hoje, pela regra (#1110, F5, §1.4): até MAX_ACTIONS ações, uma por tipo, na ordem de prioridade.
# É aqui, e não na IA, que se escolhe o tipo, o anúncio, a variante e a ordem; a IA só escreve o texto.
#
# A prioridade põe primeiro o que custa menos e rende mais: retomar proposta parada, responder mais rápido e
# arrumar o rastreio vêm antes de mexer no anúncio. O leilão é o último: só ocupa vaga que sobrou.
#
# O que a pessoa já fez hoje pesa (D5.10): a ação aceita fica na lista, marcada como aceita, mesmo que a regra já
# não falhe (com os fatos guardados na linha), e conta no teto; a dispensada sai e a vaga vai para a próxima.
# Lista vazia vira um "filler" (`wait`, `on_track`, `no_data`), que não é recomendação de trabalho: não vira linha
# em crm_meta_advisor_actions nem entra na métrica.
module Crm::MetaAds::Advisor::Decision
  KINDS = %w[stalled_quotes slow_response fix_tracking review_ad refresh_creative scale_ad auction_pressure].freeze
  FILLERS = %w[wait on_track no_data].freeze
  MAX_ACTIONS = 3
  RESPONSE_WINDOW_DAYS = 30
  # A regra de conta que dispara cada tipo de conta.
  ACCOUNT_RULE = { 'stalled_quotes' => 'stalled_quotes', 'slow_response' => 'slow_response', 'fix_tracking' => 'tracking',
                   'auction_pressure' => 'auction' }.freeze
  # Entre vários anúncios: revisão no que mais gastou; troca de imagem no que mais gastou nos últimos 7 dias;
  # escala no que vende mais barato.
  PICK = { 'review_ad' => %i[max_by spend_30d], 'refresh_creative' => %i[max_by spend_recent], 'scale_ad' => %i[min_by cost_per_sale] }.freeze

  module_function

  # today: { [kind, subject_key] => { status:, facts:, variant: } } das ações já gravadas hoje.
  # → [{ kind:, subject_key:, variant:, ad_id:, position:, status:, facts: }] (status nil nos fillers).
  def for(facts, rules, today:)
    facts = facts.deep_symbolize_keys
    rules = rules.map(&:deep_symbolize_keys)
    candidates = KINDS.filter_map { |kind| candidate(kind, facts, rules, today) }
    list = fill(accepted(today, candidates), candidates, today)
    list = [filler(facts[:ads])] if list.empty?
    list.sort_by { |action| KINDS.index(action[:kind]) || KINDS.size }.each_with_index.map { |action, index| action.merge(position: index + 1) }
  end

  # As vagas que sobram, pela prioridade, uma por tipo.
  def fill(list, candidates, today)
    candidates.each_with_object(list.dup) do |action, all|
      next if all.size >= MAX_ACTIONS || all.any? { |kept| kept[:kind] == action[:kind] }

      all << action.merge(status: status(today, action))
    end
  end

  def accepted(today, candidates)
    today.select { |_key, row| row[:status].to_s == 'accepted' }.map do |(kind, subject_key), row|
      fresh = candidates.find { |action| action[:kind] == kind && action[:subject_key] == subject_key }
      fresh&.merge(status: 'accepted') ||
        action(kind, row[:facts].to_h, subject_key: subject_key, variant: row[:variant]).merge(status: 'accepted')
    end
  end

  def status(today, action)
    today.dig([action[:kind], action[:subject_key]], :status).to_s == 'accepted' ? 'accepted' : 'open'
  end

  def dismissed?(today, kind, subject_key)
    today.dig([kind, subject_key], :status).to_s == 'dismissed'
  end

  def action(kind, facts, subject_key: 'account', variant: nil)
    ad_id = subject_key.delete_prefix('ad:') if subject_key.start_with?('ad:')
    { kind: kind, subject_key: subject_key, variant: variant, ad_id: ad_id, status: nil, facts: facts.deep_stringify_keys }
  end

  def candidate(kind, facts, rules, today)
    built = PICK.key?(kind) ? ad_candidate(kind, facts, rules, today) : account_candidate(kind, facts, rules)
    built unless built.nil? || dismissed?(today, built[:kind], built[:subject_key])
  end

  def account_candidate(kind, facts, rules)
    return unless rule(rules, ACCOUNT_RULE.fetch(kind))[:status] == 'fail'

    action(kind, send(:"#{kind}_facts", facts[:account]))
  end

  def stalled_quotes_facts(account)
    account[:stalled].slice(:count, :value, :days, :ad_name, :cards)
  end

  def slow_response_facts(account)
    account[:response].slice(:median_seconds, :answered, :unanswered, :target_seconds).merge(window_days: RESPONSE_WINDOW_DAYS)
  end

  def fix_tracking_facts(account)
    confidence = account[:confidence]
    total = confidence[:conversations].to_i
    known = confidence[:ad].to_i + confidence[:ad_name].to_i
    { conversations: total, unknown: total - known, identified_pct: total.zero? ? nil : known.fdiv(total) }
  end

  def auction_pressure_facts(account)
    change = (account[:cpm_recent] - account[:cpm_baseline]) / account[:cpm_baseline]
    { cpm_change_pct: change, cpm_recent: account[:cpm_recent], cpm_baseline: account[:cpm_baseline],
      window_days: Crm::MetaAds::Advisor::Rules::WINDOW_DAYS }
  end

  # O anúncio escolhido do tipo (PICK). Anúncio dispensado hoje dá a vez ao seguinte.
  def ad_candidate(kind, facts, rules, today)
    picker, field = PICK.fetch(kind)
    eligible = facts[:ads].select { |row| send(:"#{kind}?", row, rules) && !dismissed?(today, kind, "ad:#{row[:ad_id]}") }
    row = eligible.public_send(picker) { |entry| entry[field].to_f }
    row && action(kind, send(:"#{kind}_facts", row, facts[:account], rules), subject_key: "ad:#{row[:ad_id]}", variant: variant(kind, row, rules))
  end

  # Anúncio sem venda não aparece se o rastreio está ruim (o custo por venda dele não fecha).
  def review_ad?(row, rules)
    row[:verdict] == 'review' && rule(rules, 'tracking')[:status] != 'fail' &&
      %w[pass no_data].include?(rule(rules, 'data_gate', row[:ad_id])[:status])
  end

  # Anúncio que não vende pede revisão, não troca de imagem.
  def refresh_creative?(row, rules)
    rule(rules, 'fatigue', row[:ad_id])[:status] == 'fail' && row[:verdict] != 'review'
  end

  def scale_ad?(row, rules)
    rule(rules, 'scale', row[:ad_id])[:status] == 'pass' && rule(rules, 'tracking')[:status] != 'fail'
  end

  def review_ad_facts(row, account, _rules)
    { ad_name: row[:ad_name], conversations: row[:conversations], sales: row[:sales], spend: row[:spend_30d], cost_per_sale: row[:cost_per_sale],
      target_cost_per_sale: account[:target_cost_per_sale] }
  end

  def refresh_creative_facts(row, _account, rules)
    { ad_name: row[:ad_name], ctr_drop_pct: rule(rules, 'fatigue', row[:ad_id]).dig(:evidence, :ctr_drop_pct), frequency_7d: row[:frequency_7d],
      window_days: Crm::MetaAds::Advisor::Rules::WINDOW_DAYS }
  end

  def scale_ad_facts(row, account, _rules)
    rules = Crm::MetaAds::Advisor::Rules
    { ad_name: row[:ad_name], cost_per_sale: row[:cost_per_sale], target_cost_per_sale: account[:target_cost_per_sale],
      frequency_7d: row[:frequency_7d], max_increase_pct: rules::SCALE_STEP, weeks: rules::SCALE_WEEKS, cooldown_days: rules::SCALE_COOLDOWN_DAYS }
  end

  def variant(kind, row, rules)
    case kind
    when 'refresh_creative' then rule(rules, 'fatigue', row[:ad_id]).dig(:evidence, :trigger)
    when 'review_ad' then row.dig(:verdict_reason, :kind)
    end
  end

  def rule(rules, key, ad_id = nil)
    rules.find { |result| result[:key] == key && result[:ad_id] == ad_id } || {}
  end

  # A mesma regra da F3 (Panel::Action.wait_payload), com o anúncio que mais trouxe conversa.
  def filler(ads)
    best = ads.max_by { |row| row[:conversations] }
    payload = Crm::MetaAds::Panel::Action.wait_payload(best ? [{ name: best[:ad_name], conversations: best[:conversations] }] : [])
    return action(payload[:kind], {}) unless payload[:kind] == 'wait'

    action('wait', payload.slice(:ad_name, :missing_conversations), subject_key: "ad:#{best[:ad_id]}")
  end
end
