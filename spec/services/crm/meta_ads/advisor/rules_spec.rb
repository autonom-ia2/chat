require 'rails_helper'

# As regras do consultor (#1110, F5, §1.3), nos limites. Os cenários inteiros estão em scenarios_spec.rb.
RSpec.describe Crm::MetaAds::Advisor::Rules do
  def account(**overrides)
    {
      spend_30d: 600.0, conversations_30d: 25, quotes_30d: 4, open_quotes: 0, sales_30d: 4, target_cost_per_sale: 150.0, selling_ads: 1,
      impressions_recent: 5_000, impressions_baseline: 12_000, link_clicks_recent: 75, link_clicks_baseline: 180, spend_recent: 100.0,
      spend_baseline: 240.0, ctr_recent: 0.015, ctr_baseline: 0.015, cpm_recent: 20.0, cpm_baseline: 20.0,
      confidence: { conversations: 25, ad: 25, ad_name: 0, unknown: 0 },
      stalled: { count: 0, value: 0, days: 3, ad_name: nil, cards: [] },
      response: { days: 30, median_seconds: 60, answered: 25, unanswered: 0, slow: 0, target_seconds: 300 }
    }.merge(overrides)
  end

  def ad(**overrides)
    {
      ad_id: 'A', ad_name: 'Promo', adset_id: 'SA', verdict: 'up', verdict_reason: { kind: 'below_average' }, spend_30d: 600.0,
      conversations: 25, quotes: 4, sales: 4, cost_per_sale: 150.0, spend_recent: 100.0, impressions_recent: 5_000,
      impressions_baseline: 12_000, link_clicks_recent: 75, link_clicks_baseline: 180, ctr_recent: 0.015, ctr_baseline: 0.015,
      frequency_7d: 2.0, frequency_date_end: '2026-10-06', adset_meta_results_7d: 60, adset_spend_recent: 100.0,
      week_a: { spend: 140.0, sales: 1, cost_per_sale: 140.0 }, week_b: { spend: 140.0, sales: 1, cost_per_sale: 140.0 }
    }.merge(overrides)
  end

  def evaluate(account_facts: account, ads: [ad], accepted: [])
    described_class.evaluate({ local_date: '2026-10-07', currency: 'BRL', account: account_facts, ads: ads },
                             history: { scale_accepted_ad_ids: accepted })
  end

  def status(key, ad_id = nil, **)
    evaluate(**).find { |rule| rule[:key] == key && rule[:ad_id] == ad_id }[:status]
  end

  def rule(key, ad_id = nil, **)
    evaluate(**).find { |result| result[:key] == key && result[:ad_id] == ad_id }
  end

  it 'devolve as 4 regras de conta e as 4 de cada anúncio, com escopo, evidência e limiar' do
    results = evaluate(ads: [ad, ad(ad_id: 'B')])

    expect(results.map { |result| [result[:key], result[:ad_id]] }).to eq(
      described_class::ACCOUNT_RULES.map { |key| [key, nil] } + %w[A B].flat_map { |id| described_class::AD_RULES.map { |key| [key, id] } }
    )
    expect(results.first).to include(scope: 'account', status: 'not_applicable', threshold: { days: 3 })
    expect(rule('scale', 'A')).to include(scope: 'ad', status: 'pass')
    expect(rule('scale', 'A')[:evidence]).to include(target_cost_per_sale: 150.0, selling_ads: 1, target_includes_ad: true, week_a: 'pass',
                                                     cooldown: 'pass')
  end

  it 'tempo de resposta: mediana acima de 5 min ou 20% sem resposta; menos de 10 respostas é sem dado' do
    response = { days: 30, median_seconds: 300, answered: 8, unanswered: 2, slow: 0, target_seconds: 300 }

    expect(status('slow_response', account_facts: account(response: response))).to eq('fail')
    expect(status('slow_response', account_facts: account(response: response.merge(answered: 9, unanswered: 1)))).to eq('pass')
    expect(status('slow_response', account_facts: account(response: response.merge(answered: 9, unanswered: 1, median_seconds: 301))))
      .to eq('fail')
    expect(status('slow_response', account_facts: account(response: response.merge(answered: 9, unanswered: 0)))).to eq('no_data')
    expect(status('slow_response', account_facts: account(conversations_30d: 0))).to eq('not_applicable')
  end

  it 'leilão: CPM 30% mais caro com o clique estável; com o clique caindo é fadiga, não leilão' do
    expect(status('auction', account_facts: account(cpm_recent: 26.0, ctr_recent: 0.0136))).to eq('fail')
    expect(status('auction', account_facts: account(cpm_recent: 26.0, ctr_recent: 0.013))).to eq('pass')
    expect(status('auction', account_facts: account(link_clicks_baseline: 29))).to eq('no_data')
    expect(status('auction', account_facts: account(spend_recent: 0.0))).to eq('not_applicable')
  end

  it 'fadiga: CTR só conta mensurável; qualquer parte que falha vence a que não tem dado' do
    expect(rule('fatigue', 'A', ads: [ad(ctr_recent: 0.011)])[:evidence]).to include(trigger: 'ctr', ctr: 'fail', frequency: 'pass')
    expect(status('fatigue', 'A', ads: [ad(link_clicks_baseline: 29, ctr_recent: 0.001)])).to eq('no_data')
    expect(status('fatigue', 'A', ads: [ad(link_clicks_baseline: 29, frequency_7d: nil)])).to eq('no_data')
    expect(rule('fatigue', 'A', ads: [ad(impressions_recent: 999, frequency_7d: 4.1)])).to include(status: 'fail')
    expect(rule('fatigue', 'A', ads: [ad(ctr_recent: 0.01, frequency_7d: 4.6)])[:evidence]).to include(trigger: 'both', frequency_7d: 4.6)
    expect(status('fatigue', 'A', ads: [ad(frequency_7d: 4.0)])).to eq('pass')
    expect(status('fatigue', 'A', ads: [ad(spend_recent: 0.0)])).to eq('not_applicable')
  end

  it 'portão de dados: 3 vezes o custo-alvo; sem venda na conta é sem dado' do
    expect(status('data_gate', 'A', ads: [ad(spend_30d: 450.0)])).to eq('pass')
    expect(status('data_gate', 'A', ads: [ad(spend_30d: 449.99)])).to eq('fail')
    expect(status('data_gate', 'A', account_facts: account(target_cost_per_sale: nil))).to eq('no_data')
    expect(status('data_gate', 'A', ads: [ad(spend_30d: 0.0)])).to eq('not_applicable')
  end

  it 'aprendizado pelo conjunto: sem conversa contada pela Meta ou sem conjunto é sem dado' do
    expect(status('learning', 'A', ads: [ad(adset_meta_results_7d: 49)])).to eq('fail')
    expect(status('learning', 'A', ads: [ad(adset_meta_results_7d: 0)])).to eq('no_data')
    expect(status('learning', 'A', ads: [ad(adset_id: nil)])).to eq('no_data')
    expect(status('learning', 'A', ads: [ad(adset_spend_recent: 0.0)])).to eq('not_applicable')
  end

  it 'escala: cada parte barra; semana sem gasto é sem dado; só anúncio "aumentar" entra' do
    expect(status('scale', 'A', ads: [ad(week_b: { spend: 0.0, sales: 0, cost_per_sale: nil })])).to eq('no_data')
    expect(status('scale', 'A', ads: [ad(week_b: { spend: 90.0, sales: 0, cost_per_sale: nil })])).to eq('fail')
    expect(status('scale', 'A', ads: [ad(week_a: { spend: 151.0, sales: 1, cost_per_sale: 151.0 })])).to eq('fail')
    expect(status('scale', 'A', ads: [ad(frequency_7d: 3.0)])).to eq('fail')
    expect(status('scale', 'A', ads: [ad(frequency_7d: nil)])).to eq('no_data')
    expect(status('scale', 'A', accepted: ['A'])).to eq('fail')
    expect(status('scale', 'A', ads: [ad(verdict: 'keep')])).to eq('not_applicable')
  end

  it 'rastreio: menos de 70% identificadas falha; amostra pequena é sem dado' do
    expect(status('tracking', account_facts: account(confidence: { conversations: 10, ad: 6, ad_name: 0, unknown: 4 }))).to eq('fail')
    expect(status('tracking', account_facts: account(confidence: { conversations: 10, ad: 5, ad_name: 2, unknown: 3 }))).to eq('pass')
    expect(status('tracking', account_facts: account(confidence: { conversations: 4, ad: 0, ad_name: 0, unknown: 4 }))).to eq('no_data')
  end
end
