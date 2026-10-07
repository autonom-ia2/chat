require 'rails_helper'

# Onde a ação do dia da IA fica guardada (#1100, F4a): a assinatura ignora o gasto, o teto é por conta e por dia.
RSpec.describe Crm::MetaAds::Panel::AiActionCache do
  around do |example|
    travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) { example.run }
  end

  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:report) do
    { days: 7, totals: { spend: 100.0, quotes: 2, open_quotes: 1, sales: 1 }, ads: [{ ad_id: '1', verdict: 'early', spend: 100.0 }],
      confidence: { conversations: 4, ad: 4, ad_name: 0 },
      action: { kind: 'stalled_quotes', count: 1, cards: [{ id: 7, title: 'Maria', value: 10.0 }] } }
  end
  let(:ai_result) { { source: 'ai', reason: nil, kind: 'stalled_quotes', headline: 'Retome a proposta.', days: 7 } }

  def cache(data = report)
    described_class.new(connection: connection, report: data, zone: zone, locale: 'pt_BR')
  end

  after do
    Redis::Alfred.scan_each(match: "#{described_class::PREFIX}:*") { |key| Redis::Alfred.delete(key) }
  end

  it 'guarda até o fim do dia e devolve o guardado' do
    cache.write(ai_result)

    expect(cache.read).to eq(ai_result)
    expect(cache.fetch { raise 'não gera de novo' }).to eq(ai_result)
    key = "#{described_class::PREFIX}:#{account.id}:7:2026-10-06:pt_BR:#{cache.signature}"
    expect(Redis::Alfred.ttl(key)).to be_within(5).of(9.hours.to_i)
  end

  it 'gasto e título do card não mudam a assinatura; propostas e veredito mudam' do
    signature = cache.signature

    expect(cache(report.deep_merge(totals: { spend: 999.0 }, ads: [{ ad_id: '1', verdict: 'early', spend: 999.0 }])).signature).to eq(signature)
    expect(cache(report.deep_merge(action: { cards: [{ id: 7, title: 'Outro nome', value: 10.0 }] })).signature).to eq(signature)
    expect(cache(report.deep_merge(totals: { quotes: 3 })).signature).not_to eq(signature)
    expect(cache(report.merge(ads: [{ ad_id: '1', verdict: 'review' }])).signature).not_to eq(signature)
  end

  it 'falha do provedor fica 15 minutos' do
    cache.write(ai_result.merge(source: 'rule', reason: 'ai_error'))

    key = "#{described_class::PREFIX}:#{account.id}:7:2026-10-06:pt_BR:#{cache.signature}"
    expect(Redis::Alfred.ttl(key)).to be_within(5).of(15.minutes.to_i)
    expect(cache.last).to be_nil
  end

  it 'teto de 6 gerações por conta por dia, e o último texto da IA continua disponível' do
    expect(Array.new(6) { cache.reserve! }).to all(be(true))
    expect(cache.reserve!).to be(false)

    cache(report.deep_merge(totals: { quotes: 5 })).write(ai_result)
    expect(cache.last).to eq(ai_result)
  end
end
