require 'rails_helper'

RSpec.describe Crm::Reports::AiUsage do
  around do |example|
    travel_to(Time.zone.parse('2026-06-28 12:00:00')) { example.run }
  end

  before do
    allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: BigDecimal('5.50'), fetched_at: Time.current.iso8601,
                                                                 rate_unavailable: false)
    allow(Crm::Ai::UsageBroadcaster).to receive(:broadcast)
  end

  def payload(account:, params: {})
    described_class.new(account: account, params: params.reverse_merge(since: 1.week.ago.iso8601, until: Time.current.iso8601)).perform
  end

  it 'returns top aggregates, decimal BRL conversion and cache savings percentage' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, model: 'gpt-5.4-mini', input_tokens: 1000, cached_tokens: 100,
                                output_tokens: 200, cost_estimate: 0.001575)
    create(:crm_ai_usage_event, account: account, model: 'gpt-5.4', input_tokens: 2000, cached_tokens: 500,
                                output_tokens: 100, cost_estimate: 0.005375)

    result = payload(account: account)

    expect(result.dig(:totals, :usage_count)).to eq(2)
    expect(result.dig(:totals, :period_spend, :cost_usd)).to be_within(0.000001).of(0.00695)
    expect(result.dig(:totals, :period_spend, :cost_brl)).to be_within(0.000001).of(0.038225)
    expect(result.dig(:totals, :average_cost, :cost_usd)).to be_within(0.000001).of(0.003475)

    # (100 * (0.75 - 0.075) + 500 * (2.5 - 0.25)) / 1_000_000 = 0.0011925
    expect(result.dig(:totals, :cache_savings, :cost_usd)).to be_within(0.000001).of(0.001193)
    expect(result.dig(:totals, :cache_savings_pct)).to be_within(0.01).of(14.64)
  end

  it 'reports cache savings net of the cache write premium on the 5.6 family' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, model: 'gpt-5.6-luna', input_tokens: 2000,
                                cached_tokens: 1000, cache_write_tokens: 800, output_tokens: 100,
                                cost_estimate: 0.01)

    result = payload(account: account)

    # leitura: 1000 * (1.0 - 0.1) = 900 ; escrita: 800 * (1.25 - 1.0) = 200
    # líquido = (900 - 200) / 1_000_000 = 0.0007
    expect(result.dig(:totals, :cache_savings, :cost_usd)).to be_within(0.000001).of(0.0007)
  end

  it 'keeps cache savings untouched for models without a cache write rate' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, model: 'gpt-5.4', input_tokens: 2000,
                                cached_tokens: 500, cache_write_tokens: 900, output_tokens: 100,
                                cost_estimate: 0.01)

    result = payload(account: account)

    # gpt-5.4 não cobra cache write -> sobretaxa zero, só o desconto de leitura
    # 500 * (2.5 - 0.25) / 1_000_000 = 0.001125
    expect(result.dig(:totals, :cache_savings, :cost_usd)).to be_within(0.000001).of(0.001125)
  end

  it 'groups real feature strings into humanized resources and keeps unknown features as Outros' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, feature: 'resumo', cost_estimate: 0.01)
    create(:crm_ai_usage_event, account: account, feature: 'resumo_reuniao', cost_estimate: 0.02)
    create(:crm_ai_usage_event, account: account, feature: 'kb_instrucao', cost_estimate: 0.03)
    create(:crm_ai_usage_event, account: account, feature: 'feature_nova', cost_estimate: 0.04)

    resources = payload(account: account)[:spend_by_resource].index_by { |row| row[:resource] }

    expect(resources['Resumos'][:usage_count]).to eq(2)
    expect(resources['Resumos'][:cost_usd]).to be_within(0.000001).of(0.03)
    expect(resources['Base de conhecimento'][:usage_count]).to eq(1)
    expect(resources['Outros'][:usage_count]).to eq(1)
  end

  it 'scopes data to account, since/until and optional pipeline without defaulting to a pipeline' do
    account = create(:account)
    other_account = create(:account)
    admin = create(:user, account: account, role: :administrator)
    pipeline, = create_crm_pipeline(account: account, user: admin)
    other_pipeline, = create_crm_pipeline(account: account, user: admin, name: 'Outro funil')

    create(:crm_ai_usage_event, account: account, pipeline_id: pipeline.id, cost_estimate: 0.01, created_at: 1.day.ago)
    create(:crm_ai_usage_event, account: account, pipeline_id: nil, cost_estimate: 0.02, created_at: 1.day.ago)
    create(:crm_ai_usage_event, account: account, pipeline_id: other_pipeline.id, cost_estimate: 0.03, created_at: 1.day.ago)
    create(:crm_ai_usage_event, account: other_account, cost_estimate: 0.04, created_at: 1.day.ago)
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.05, created_at: 10.days.ago)

    all_pipelines = payload(account: account)
    only_pipeline = payload(account: account, params: { pipeline_id: pipeline.id, since: 1.week.ago.iso8601, until: Time.current.iso8601 })

    expect(all_pipelines.dig(:totals, :usage_count)).to eq(3)
    expect(all_pipelines.dig(:totals, :period_spend, :cost_usd)).to be_within(0.000001).of(0.06)
    expect(only_pipeline.dig(:totals, :usage_count)).to eq(1)
    expect(only_pipeline.dig(:totals, :period_spend, :cost_usd)).to be_within(0.000001).of(0.01)
  end

  it 'builds a time series by the selected group_by' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.01, created_at: Time.zone.parse('2026-06-28 10:05:00'))
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.02, created_at: Time.zone.parse('2026-06-28 10:45:00'))
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.03, created_at: Time.zone.parse('2026-06-28 11:05:00'))

    series = payload(account: account, params: { group_by: 'hour', since: Time.zone.parse('2026-06-28').iso8601,
                                                 until: Time.current.iso8601 })[:time_series]

    expect(series.map { |point| point[:timestamp] }).to eq(['2026-06-28T10:00:00Z', '2026-06-28T11:00:00Z'])
    expect(series.first[:cost_usd]).to be_within(0.000001).of(0.03)
    expect(series.second[:cost_usd]).to be_within(0.000001).of(0.03)
  end

  it 'paginates history and never serializes model' do
    account = create(:account)
    create_list(:crm_ai_usage_event, 30, account: account, model: 'gpt-5.4', cost_estimate: 0.01)

    result = payload(account: account, params: { page: 2 })
    serialized = result.to_json

    expect(result.dig(:history, :page)).to eq(2)
    expect(result.dig(:history, :per_page)).to eq(25)
    expect(result.dig(:history, :total_count)).to eq(30)
    expect(result.dig(:history, :rows).size).to eq(5)
    expect(serialized).not_to include('model')
    expect(serialized).not_to include('prompt')
    expect(serialized).not_to include('response')
  end

  it 'floors the window at CRM_AI_USAGE_BASELINE_AT, hiding pre-baseline events without deleting them' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.01, created_at: Time.zone.parse('2026-06-27 09:00:00'))
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.02, created_at: Time.zone.parse('2026-06-28 09:00:00'))

    with_modified_env CRM_AI_USAGE_BASELINE_AT: '2026-06-28 00:00:00' do
      result = payload(account: account)

      expect(result.dig(:totals, :usage_count)).to eq(1)
      expect(result.dig(:totals, :period_spend, :cost_usd)).to be_within(0.000001).of(0.02)
      expect(result.dig(:period, :since)).to eq(Time.zone.parse('2026-06-28 00:00:00').iso8601)
    end
  end

  it 'ignores the baseline when the ENV is unset (no regression)' do
    account = create(:account)
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.01, created_at: Time.zone.parse('2026-06-27 09:00:00'))
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.02, created_at: Time.zone.parse('2026-06-28 09:00:00'))

    expect(payload(account: account).dig(:totals, :usage_count)).to eq(2)
  end

  it 'marks BRL values unavailable when no exchange rate is available' do
    allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: nil, rate_unavailable: true)
    account = create(:account)
    create(:crm_ai_usage_event, account: account, cost_estimate: 0.01)

    result = payload(account: account)

    expect(result.dig(:exchange_rate, :rate_unavailable)).to be(true)
    expect(result.dig(:totals, :period_spend, :cost_usd)).to eq(0.01)
    expect(result.dig(:totals, :period_spend, :cost_brl)).to be_nil
    expect(result.dig(:totals, :period_spend, :rate_unavailable)).to be(true)
  end
end
