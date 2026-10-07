require 'rails_helper'

# Os fatos do consultor (#1110, F5, §1.2): JSON puro, sem título de card nem contato, 5 min no Redis e o Report
# de 30 dias da requisição reaproveitado.
RSpec.describe Crm::MetaAds::Advisor::Facts do
  around do |example|
    travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) { example.run }
  end

  let!(:setup) { advisor_setup }
  let(:connection) { setup.last }
  let(:key) { described_class.cache_key(connection, Date.new(2026, 10, 7)) }

  before do
    # Linha de base de R$ 210 em 21 dias (R$ 10 por dia, R$ 70 por semana) e R$ 100 nos últimos 7.
    advisor_insights(ad_id: 'A', adset_id: 'SA', from: Date.new(2026, 9, 9), to: Date.new(2026, 9, 29), spend: 210, impressions: 12_000,
                     link_clicks: 180)
    advisor_insights(ad_id: 'A', adset_id: 'SA', from: Date.new(2026, 9, 30), to: Date.new(2026, 10, 6), spend: 100, impressions: 5_000,
                     link_clicks: 50, conversations_started: 10)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.5)
    conversations = advisor_conversations(ad_id: 'A', count: 4, from: Date.new(2026, 9, 24), to: Date.new(2026, 9, 27))
    advisor_sale(conversations.first)
    advisor_stalled_quote(conversations.last)
    Redis::Alfred.delete(key)
  end

  after { Redis::Alfred.delete(key) }

  def queries(&)
    list = []
    callback = ->(*, payload) { list << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    list
  end

  it 'calcula as janelas no fuso da conta, com datas em ISO 8601 e sem título de card' do
    payload = described_class.new(connection).payload
    account = payload[:account]
    ad = payload[:ads].sole

    expect(payload.slice(:local_date, :currency)).to eq(local_date: '2026-10-07', currency: 'BRL')
    expect(account).to include(spend_30d: 310.0, conversations_30d: 4, quotes_30d: 2, open_quotes: 1, sales_30d: 1, target_cost_per_sale: 310.0,
                               selling_ads: 1, impressions_recent: 5_000, impressions_baseline: 12_000, link_clicks_baseline: 180,
                               ctr_recent: 0.01, cpm_baseline: 17.5)
    expect(account[:stalled]).to include(count: 1, value: 1500.0, days: 3, ad_name: 'Anúncio A')
    expect(account[:stalled][:cards].sole.keys).to contain_exactly(:id, :value, :conversation_id, :waiting_since)
    expect(ad).to include(ad_id: 'A', adset_id: 'SA', frequency_7d: 2.5, frequency_date_end: '2026-10-06', adset_meta_results_7d: 10,
                          adset_spend_recent: 100.0, week_a: { spend: 70.0, sales: 1, cost_per_sale: 70.0 },
                          week_b: { spend: 70.0, sales: 0, cost_per_sale: nil })
    expect(payload.to_json).not_to include('Cotação')
  end

  it 'guarda no Redis por 5 min: a segunda leitura não consulta o banco' do
    first = described_class.new(connection).payload

    second = nil
    expect(queries { second = described_class.new(connection).payload }).to be_empty
    expect(second).to eq(first)
  end

  it 'reaproveita o Report de 30 dias da requisição, e não o de 7' do
    report = Crm::MetaAds::Panel::Report.new(connection, days: 30)
    allow(Crm::MetaAds::Panel::Report).to receive(:new).and_call_original

    described_class.new(connection, report: report).payload
    expect(Crm::MetaAds::Panel::Report).not_to have_received(:new)

    Redis::Alfred.delete(key)
    described_class.new(connection, report: Crm::MetaAds::Panel::Report.new(connection, days: 7)).payload
    expect(Crm::MetaAds::Panel::Report).to have_received(:new).with(connection, days: 30)
  end
end
