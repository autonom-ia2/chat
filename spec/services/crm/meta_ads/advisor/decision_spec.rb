require 'rails_helper'

# O que fazer hoje pela regra (#1110, F5, §1.4): prioridade, teto de 3, uma por tipo, aceitas ficam, dispensadas
# saem e a vaga vai para a próxima. Os cenários inteiros estão em scenarios_spec.rb.
RSpec.describe Crm::MetaAds::Advisor::Decision do
  let(:account) do
    {
      target_cost_per_sale: 150.0, cpm_recent: 28.0, cpm_baseline: 20.0,
      confidence: { conversations: 10, ad: 5, ad_name: 1, unknown: 4 },
      stalled: { count: 2, value: 3000.0, days: 3, ad_name: 'Promo', cards: [{ id: 9, value: 1500.0 }] },
      response: { days: 30, median_seconds: 1500, answered: 12, unanswered: 2, slow: 12, target_seconds: 300 }
    }
  end

  def ad(ad_id, **overrides)
    { ad_id: ad_id, ad_name: "Anúncio #{ad_id}", verdict: 'signal', verdict_reason: { kind: 'signal' }, spend_30d: 100.0, spend_recent: 50.0,
      conversations: 25, sales: 1, cost_per_sale: 100.0, frequency_7d: 2.0 }.merge(overrides)
  end

  def rule(key, status, ad_id = nil, evidence: {})
    { key: key, scope: ad_id ? 'ad' : 'account', ad_id: ad_id, status: status, evidence: evidence, threshold: {} }
  end

  def account_rules(stalled: 'pass', slow: 'pass', tracking: 'pass', auction: 'pass')
    [rule('stalled_quotes', stalled), rule('slow_response', slow), rule('tracking', tracking), rule('auction', auction)]
  end

  def ad_rules(ad_id, data_gate: 'fail', fatigue: 'pass', scale: 'not_applicable', trigger: nil)
    [rule('data_gate', data_gate, ad_id), rule('learning', 'fail', ad_id),
     rule('fatigue', fatigue, ad_id, evidence: { trigger: trigger, ctr_drop_pct: 0.33 }), rule('scale', scale, ad_id)]
  end

  def decide(ads:, rules:, today: {})
    described_class.for({ local_date: '2026-10-07', account: account, ads: ads }, rules, today: today)
  end

  def kinds(actions)
    actions.map { |action| [action[:kind], action[:ad_id], action[:status], action[:position]] }
  end

  it 'segue a prioridade, uma por tipo, no máximo 3, e o leilão fica de fora quando não há vaga' do
    actions = decide(ads: [ad('A')], rules: account_rules(stalled: 'fail', slow: 'fail', tracking: 'fail', auction: 'fail') + ad_rules('A'))

    expect(kinds(actions)).to eq([['stalled_quotes', nil, 'open', 1], ['slow_response', nil, 'open', 2], ['fix_tracking', nil, 'open', 3]])
    expect(actions.first).to include(subject_key: 'account', variant: nil)
    expect(actions.first[:facts]).to eq('count' => 2, 'value' => 3000.0, 'days' => 3, 'ad_name' => 'Promo',
                                        'cards' => [{ 'id' => 9, 'value' => 1500.0 }])
    expect(actions.second[:facts]).to eq('median_seconds' => 1500, 'answered' => 12, 'unanswered' => 2, 'target_seconds' => 300,
                                         'window_days' => 30)
    expect(actions.third[:facts]).to eq('conversations' => 10, 'unknown' => 4, 'identified_pct' => 0.6)
  end

  it 'dispensada hoje sai e a vaga vai para a próxima; aceita fica, mesmo sem a regra, com os fatos guardados' do
    today = {
      %w[stalled_quotes account] => { status: 'dismissed', facts: {} },
      ['scale_ad', 'ad:B'] => { status: 'accepted', variant: nil, facts: { 'ad_name' => 'Anúncio B', 'cost_per_sale' => 90.0 } }
    }

    actions = decide(ads: [ad('A')], rules: account_rules(stalled: 'fail', slow: 'fail', tracking: 'fail', auction: 'fail') + ad_rules('A'),
                     today: today)

    expect(kinds(actions)).to eq([['slow_response', nil, 'open', 1], ['fix_tracking', nil, 'open', 2], ['scale_ad', 'B', 'accepted', 3]])
    expect(actions.last[:facts]).to eq('ad_name' => 'Anúncio B', 'cost_per_sale' => 90.0)
  end

  it 'aceita que ainda é candidata fica com os fatos atuais e marcada como aceita' do
    today = { %w[stalled_quotes account] => { status: 'accepted', facts: { 'count' => 7 } } }

    actions = decide(ads: [], rules: account_rules(stalled: 'fail'), today: today)

    expect(kinds(actions)).to eq([['stalled_quotes', nil, 'accepted', 1]])
    expect(actions.sole[:facts]['count']).to eq(2)
  end

  # Uma aba atrasada aceitou a revisão do anúncio A (de um run anterior do dia) e a pessoa aceitou também a do B,
  # que a regra escolhe agora: o teto e "uma por tipo" valem para as aceitas também.
  it 'aceitas de runs anteriores do dia: uma por tipo, a da decisão de agora, e no máximo 3' do
    ads = [ad('A', verdict: 'review', verdict_reason: { kind: 'no_sales' }, spend_30d: 100.0),
           ad('B', verdict: 'review', verdict_reason: { kind: 'no_sales' }, spend_30d: 300.0)]
    today = {
      %w[stalled_quotes account] => { status: 'accepted', position: 1, facts: { 'count' => 2 } },
      %w[slow_response account] => { status: 'accepted', position: 2, facts: { 'median_seconds' => 1500 } },
      ['review_ad', 'ad:A'] => { status: 'accepted', position: 3, variant: 'no_sales', facts: { 'ad_name' => 'Anúncio A' } },
      ['review_ad', 'ad:B'] => { status: 'accepted', position: 3, variant: 'no_sales', facts: { 'ad_name' => 'Anúncio B' } }
    }
    rules = account_rules(stalled: 'fail', slow: 'fail') + ad_rules('A', data_gate: 'pass') + ad_rules('B', data_gate: 'pass')

    actions = decide(ads: ads, rules: rules, today: today)

    expect(kinds(actions)).to eq([['stalled_quotes', nil, 'accepted', 1], ['slow_response', nil, 'accepted', 2], ['review_ad', 'B', 'accepted', 3]])
  end

  it 'revisão no anúncio que mais gastou; anúncio dispensado dá a vez ao seguinte; rastreio ruim bloqueia' do
    ads = [ad('A', verdict: 'review', verdict_reason: { kind: 'no_sales' }, spend_30d: 300.0),
           ad('B', verdict: 'review', verdict_reason: { kind: 'above_average' }, spend_30d: 200.0)]
    rules = account_rules + ad_rules('A', data_gate: 'no_data') + ad_rules('B', data_gate: 'pass')

    expect(decide(ads: ads, rules: rules).sole).to include(kind: 'review_ad', ad_id: 'A', variant: 'no_sales', subject_key: 'ad:A')
    expect(decide(ads: ads, rules: rules).sole[:facts]).to eq(
      'ad_name' => 'Anúncio A', 'conversations' => 25, 'sales' => 1, 'spend' => 300.0, 'cost_per_sale' => 100.0,
      'target_cost_per_sale' => 150.0, 'window_days' => 30
    )
    expect(decide(ads: ads, rules: rules, today: { ['review_ad', 'ad:A'] => { status: 'dismissed' } }).sole)
      .to include(kind: 'review_ad', ad_id: 'B', variant: 'above_average')
    expect(decide(ads: ads, rules: account_rules(tracking: 'fail') + ad_rules('A', data_gate: 'no_data')).map { |action| action[:kind] })
      .to eq(['fix_tracking'])
  end

  it 'o portão de dados que falha barra a revisão' do
    ads = [ad('A', verdict: 'review', verdict_reason: { kind: 'no_sales' })]

    expect(decide(ads: ads, rules: account_rules + ad_rules('A', data_gate: 'fail')).sole[:kind]).to eq('on_track')
  end

  it 'anúncio que não vende pede revisão, não troca de imagem; a troca vai no que mais gastou nos últimos 7 dias' do
    ads = [ad('A', verdict: 'review', verdict_reason: { kind: 'no_sales' }), ad('B', spend_recent: 40.0), ad('C', spend_recent: 80.0)]
    rules = account_rules + ad_rules('A', data_gate: 'pass', fatigue: 'fail', trigger: 'ctr') +
            ad_rules('B', fatigue: 'fail', trigger: 'both') + ad_rules('C', fatigue: 'fail', trigger: 'frequency')

    actions = decide(ads: ads, rules: rules)

    expect(kinds(actions)).to eq([['review_ad', 'A', 'open', 1], ['refresh_creative', 'C', 'open', 2]])
    expect(actions.last).to include(variant: 'frequency')
    expect(actions.last[:facts]).to eq('ad_name' => 'Anúncio C', 'ctr_drop_pct' => 0.33, 'frequency_7d' => 2.0, 'window_days' => 7)
  end

  it 'escala no anúncio que vende mais barato, com os prazos como fatos' do
    ads = [ad('A', verdict: 'up', cost_per_sale: 120.0), ad('B', verdict: 'up', cost_per_sale: 90.0)]
    rules = account_rules + ad_rules('A', scale: 'pass') + ad_rules('B', scale: 'pass')

    expect(decide(ads: ads, rules: rules).sole).to include(kind: 'scale_ad', ad_id: 'B')
    expect(decide(ads: ads, rules: rules).sole[:facts]).to eq(
      'ad_name' => 'Anúncio B', 'cost_per_sale' => 90.0, 'target_cost_per_sale' => 150.0, 'frequency_7d' => 2.0,
      'max_increase_pct' => 0.2, 'weeks' => 2, 'cooldown_days' => 5
    )
  end

  it 'leilão traz a variação e as duas médias' do
    expect(decide(ads: [], rules: account_rules(auction: 'fail')).sole[:facts])
      .to eq('cpm_change_pct' => 0.4, 'cpm_recent' => 28.0, 'cpm_baseline' => 20.0, 'window_days' => 7)
  end

  it 'lista vazia vira filler, sem status: espera no anúncio com mais conversa, em dia, ou sem dado' do
    expect(decide(ads: [ad('A', conversations: 8), ad('B', conversations: 3)], rules: account_rules).sole)
      .to include(kind: 'wait', ad_id: 'A', subject_key: 'ad:A', status: nil, facts: { 'ad_name' => 'Anúncio A', 'missing_conversations' => 12 })
    expect(decide(ads: [ad('A')], rules: account_rules).sole).to include(kind: 'on_track', ad_id: nil, status: nil, facts: {})
    expect(decide(ads: [], rules: account_rules).sole).to include(kind: 'no_data', position: 1)
  end
end
