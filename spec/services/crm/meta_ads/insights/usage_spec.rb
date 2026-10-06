require 'rails_helper'

# Limite de uso da Insights API (#1073, CA-2.2): lê os cabeçalhos da Meta e pausa a conta de anúncios.
RSpec.describe Crm::MetaAds::Insights::Usage do
  let(:ad_account_id) { '2196424464528988' }

  after { Redis::Alfred.delete(described_class.key(ad_account_id)) }

  def result(headers: {}, error_code: nil)
    Meta::AdsGraphClient::Result.new(ok: error_code.nil?, http_code: error_code ? 400 : 200, error_code: error_code, usage_headers: headers)
  end

  def business_usage(call_count:, regain: 0)
    { '1013433763956648' => [{ type: 'ads_insights', call_count: call_count, total_cputime: 5, total_time: 5,
                               estimated_time_to_regain_access: regain }] }.to_json
  end

  it 'lê o maior percentual entre os três cabeçalhos' do
    usage = described_class.new(
      'x-business-use-case-usage' => business_usage(call_count: 40),
      'x-fb-ads-insights-throttle' => { app_id_util_pct: 12.5, acc_id_util_pct: 61 }.to_json,
      'x-app-usage' => { call_count: 3, total_cputime: 1, total_time: 1 }.to_json
    )

    expect(usage.percent).to eq(61.0)
    expect(usage.regain_time).to be_nil
  end

  it 'ignora cabeçalho que não é JSON' do
    expect(described_class.new('x-app-usage' => 'quebrado').percent).to eq(0.0)
  end

  it 'abaixo de 75% não pausa' do
    expect(described_class.track!(ad_account_id, result(headers: { 'x-business-use-case-usage' => business_usage(call_count: 74) })))
      .to be(false)
    expect(described_class.paused?(ad_account_id)).to be(false)
  end

  it 'a partir de 75% pausa pelo tempo que a Meta indica, e registra no log' do
    allow(Rails.logger).to receive(:warn)

    paused = described_class.track!(ad_account_id, result(headers: { 'x-business-use-case-usage' => business_usage(call_count: 80, regain: 20) }))

    expect(paused).to be(true)
    expect(described_class.paused?(ad_account_id)).to be(true)
    expect(Redis::Alfred.ttl(described_class.key(ad_account_id))).to be_within(5).of(20.minutes.to_i)
    expect(Rails.logger).to have_received(:warn).with(include('[MetaAdsInsights] pause', 'usage=80.0%'))
  end

  it 'erro de limite sem tempo indicado pausa pelo tempo padrão' do
    allow(Rails.logger).to receive(:warn)

    expect(described_class.track!(ad_account_id, result(error_code: 80_000))).to be(true)
    expect(Redis::Alfred.ttl(described_class.key(ad_account_id))).to be_within(5).of(described_class::DEFAULT_PAUSE.to_i)
  end

  it 'erro que não é de limite não pausa' do
    expect(described_class.track!(ad_account_id, result(error_code: 190))).to be(false)
  end
end
