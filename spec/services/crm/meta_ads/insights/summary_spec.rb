require 'rails_helper'

# O que a tela mostra da coleta (#1073): o dia no fuso da conta de anúncios, zero de hoje antes do primeiro gasto
# e a carga de 90 dias em andamento.
RSpec.describe Crm::MetaAds::Insights::Summary do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  # 06/10/2026 01:30 UTC = 05/10/2026 22:30 em São Paulo: o "hoje" da conta ainda é dia 5.
  let(:now) { Time.utc(2026, 10, 6, 1, 30) }

  after { Crm::MetaAds::Insights::Backfill.release(connection.id) }

  def insight(date, spend:, conversations: 1, ad_id: '1')
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: date, currency: 'BRL',
                                    spend: spend, conversations_started: conversations, attribution_window: '7d_click', fetched_at: now)
  end

  it 'soma o dia de hoje no fuso da conta de anúncios' do
    travel_to(now) do
      insight(Date.new(2026, 10, 5), spend: 30, conversations: 2)
      insight(Date.new(2026, 10, 5), spend: 12.5, ad_id: '2')

      payload = described_class.payload(connection, refreshing: false)

      expect(payload).to include(today: Date.new(2026, 10, 5), date: Date.new(2026, 10, 5), spend: '42.5', currency: 'BRL', conversations: 3)
    end
  end

  it 'leitura de hoje já feita e sem linha: hoje com zero, não o último dia com gasto' do
    travel_to(now) do
      insight(Date.new(2026, 10, 4), spend: 99)
      connection.update!(insights_synced_at: now)

      expect(described_class.payload(connection, refreshing: false))
        .to include(date: Date.new(2026, 10, 5), spend: '0', currency: 'BRL', conversations: 0)
    end
  end

  it 'antes da primeira leitura de hoje mostra o último dia com gasto' do
    travel_to(now) do
      insight(Date.new(2026, 10, 4), spend: 99)
      connection.update!(insights_synced_at: now - 1.day)

      expect(described_class.payload(connection, refreshing: false)).to include(date: Date.new(2026, 10, 4), spend: '99.0')
    end
  end

  it 'sem fuso conhecido não diz qual é hoje e mostra o último dia' do
    connection.update!(ad_account_timezone: nil)
    insight(Date.new(2026, 10, 4), spend: 5)

    expect(described_class.payload(connection, refreshing: false)).to include(today: nil, date: Date.new(2026, 10, 4))
  end

  it 'diz quando a carga de 90 dias está chegando' do
    Crm::MetaAds::Insights::Backfill.claim(connection.id)

    expect(described_class.payload(connection, refreshing: false)).to include(backfilling: true, date: nil)
    connection.update!(insights_backfilled_at: Time.current)
    expect(described_class.payload(connection, refreshing: false)).to include(backfilling: false)
  end
end
