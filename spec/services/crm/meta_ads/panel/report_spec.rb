require 'rails_helper'

# Painel do dia a dia (#1088, F3a, CA-3.1): números do herói, anúncios por venda e quanto confiar, do banco. A ação
# do dia saiu na F5 (#1110): é do consultor.
RSpec.describe Crm::MetaAds::Panel::Report do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account)).first }
  let(:lead_stage) { stage('Novo', 'lead', 1) }
  let(:quote_stage) { stage('Proposta', 'opportunity', 2) }
  let(:capa) { '120254710362980416' }
  let(:familia) { '120254710382780416' }
  let(:now) { Time.zone.parse('2026-10-06T15:00:00-03:00') }

  def stage(name, type, position)
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: name, position: position, metadata: { 'funnel_stage_type' => type })
  end

  def spend(ad_id, date, value)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: date, currency: 'BRL',
                                    spend: value, attribution_window: '7d_click', fetched_at: now)
  end

  def name(ad_id, text)
    Crm::MetaAdObject.create!(account: account, meta_object_id: ad_id, object_type: 'ad', name: text, fetched_at: now)
  end

  def from_ad(ad_id, at:, card: nil)
    conversation = create(:conversation, account: account)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                            certainty: ad_id ? 'ad' : 'unknown', ad_id: ad_id, touched_at: at)
    if card
      Crm::Card.create!(account: account, pipeline: pipeline, title: 'Cotação', currency: 'BRL', primary_conversation: conversation,
                        **card)
    end
    conversation
  end

  def card(stage:, status: :open, value: 0, waiting: nil)
    { stage: stage, status: status, value_cents: (value * 100).to_i, last_message_at: waiting }
  end

  it 'soma gasto, conversas, propostas e vendas do período e põe cada anúncio no seu lugar' do
    travel_to(now) do
      name(capa, 'Capa (1080x1350)')
      name(familia, 'C2 Famila')
      spend(capa, Date.new(2026, 10, 6), 100)
      spend(capa, Date.new(2026, 9, 1), 999) # fora dos 30 dias
      spend(familia, Date.new(2026, 10, 5), 50)
      from_ad(capa, at: 1.day.ago, card: card(stage: quote_stage, status: :won, value: 622.64))
      from_ad(capa, at: 2.days.ago, card: card(stage: quote_stage, waiting: 1.hour.ago))
      from_ad(familia, at: 1.day.ago, card: card(stage: lead_stage))
      from_ad(nil, at: 1.day.ago)

      report = described_class.new(connection, days: 30).payload

      expect(report[:totals]).to include(spend: 150.0, conversations: 4, quotes: 2, open_quotes: 1, sales: 1, sales_value: 622.64,
                                         cost_per_conversation: 37.5, cost_per_sale: 150.0, return_per_real: 4.15)
      expect(report[:ads].map { |ad| ad.slice(:name, :spend, :conversations, :quotes, :sales, :verdict) }).to eq(
        [{ name: 'Capa (1080x1350)', spend: 100.0, conversations: 2, quotes: 2, sales: 1, verdict: 'early' },
         { name: 'C2 Famila', spend: 50.0, conversations: 1, quotes: 0, sales: 0, verdict: 'early' }]
      )
      expect(report).to include(days: 30, from: Date.new(2026, 9, 7), to: Date.new(2026, 10, 6), currency: 'BRL')
    end
  end

  it '7 dias olha só a última semana' do
    travel_to(now) do
      spend(capa, Date.new(2026, 10, 6), 10)
      spend(capa, Date.new(2026, 9, 25), 90)
      from_ad(capa, at: 10.days.ago)

      totals = described_class.new(connection, days: 7).payload[:totals]

      expect(totals).to include(spend: 10.0, conversations: 0, cost_per_conversation: nil, return_per_real: nil)
    end
  end

  it 'não traz mais a ação do dia: ela é do consultor, que não depende do período (F5, D5.2)' do
    travel_to(now) do
      from_ad(capa, at: 6.days.ago, card: card(stage: quote_stage, value: 842, waiting: 4.days.ago))

      expect(described_class.new(connection, days: 30).payload).not_to have_key(:action)
    end
  end

  it 'quanto confiar segue o período do painel (F5, D5.8)' do
    travel_to(now) do
      from_ad(capa, at: 1.day.ago)
      from_ad(nil, at: 2.days.ago)
      from_ad(capa, at: 10.days.ago)

      expect(described_class.new(connection, days: 7).payload[:confidence])
        .to eq(window_days: 7, conversations: 2, ad: 1, ad_name: 0, campaign: 0, unknown: 1)
      expect(described_class.new(connection, days: 30).payload[:confidence]).to include(window_days: 30, conversations: 3, ad: 2)
    end
  end

  it 'período fora da lista vira 30 dias' do
    expect(described_class.new(connection, days: '365').payload[:days]).to eq(30)
  end
end
