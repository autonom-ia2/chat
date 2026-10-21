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

  def spend(ad_id, date, value, **metrics)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: date, currency: 'BRL',
                                    spend: value, attribution_window: '7d_click', fetched_at: now, **metrics)
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

  def adset(id, destination)
    Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'adset', name: "Conjunto #{id}", destination_type: destination,
                              fetched_at: now)
  end

  # #2054: o gasto de anúncio que leva para fora de conversa não entra no custo por conversa nem por venda.
  it 'separa os anúncios que trazem conversa dos que levam ao site, com gasto, cliques e impressões' do
    travel_to(now) do
      site = '120254932730050416'
      name(site, 'EUA')
      adset('set-site', 'WEBSITE')
      spend(capa, Date.new(2026, 10, 6), 100)
      spend(familia, Date.new(2026, 10, 5), 50, conversations_started: 2)
      spend(familia, Date.new(2026, 7, 1), 1, conversations_started: 3) # a Meta já contou conversa nele, noutra época
      spend(site, Date.new(2026, 10, 5), 101.71, link_clicks: 540, impressions: 9000, adset_id: 'set-site')
      from_ad(capa, at: 1.day.ago, card: card(stage: quote_stage, status: :won, value: 500))

      report = described_class.new(connection, period: '30d').payload

      expect(report[:ads].pluck(:ad_id)).to eq([capa, familia])
      expect(report[:other_ads]).to eq([{ ad_id: site, spend: 101.71, impressions: 9000, link_clicks: 540, name: 'EUA',
                                          thumbnail_url: nil, image_url: nil }])
      expect(report[:totals]).to include(spend: 150.0, other_spend: 101.71, cost_per_conversation: 150.0, cost_per_sale: 150.0)
    end
  end

  it 'anúncio novo de WhatsApp, ou sem destino conhecido, ainda sem conversa, segue entre os que trazem conversa' do
    travel_to(now) do
      adset('set-zap', 'WHATSAPP')
      adset('set-indefinido', 'UNDEFINED')
      adset('set-site', 'WEBSITE')
      spend('novo-zap', Date.new(2026, 10, 6), 30, adset_id: 'set-zap')
      spend('sem-destino', Date.new(2026, 10, 6), 20)
      spend('indefinido', Date.new(2026, 10, 6), 10, adset_id: 'set-indefinido')
      spend('site-com-conversa', Date.new(2026, 10, 6), 40, adset_id: 'set-site')
      from_ad('site-com-conversa', at: 1.day.ago) # landing page que levou ao WhatsApp

      report = described_class.new(connection, period: '30d').payload

      expect(report[:ads].pluck(:ad_id)).to contain_exactly('novo-zap', 'sem-destino', 'indefinido', 'site-com-conversa')
      expect(report[:other_ads]).to be_empty
      expect(report[:totals]).to include(spend: 100.0, other_spend: 0.0)
    end
  end

  it 'o conjunto resolvido depois manda o anúncio para os outros, mesmo sem o conjunto no gasto' do
    travel_to(now) do
      adset('set-video', 'ON_VIDEO')
      Crm::MetaAdObject.create!(account: account, meta_object_id: 'video', object_type: 'ad', name: 'Vídeo', adset_id: 'set-video', fetched_at: now)
      spend('video', Date.new(2026, 10, 6), 25)

      expect(described_class.new(connection, period: '30d').payload[:other_ads].pluck(:ad_id)).to eq(['video'])
    end
  end

  it 'logo depois de conectar, o anúncio sem nome da Meta usa o título do clique' do
    travel_to(now) do
      conversation = from_ad(capa, at: 1.day.ago)
      touch = { 'source' => 'meta_ctwa', 'source_id' => capa, 'headline' => 'Fale com a gente' }
      conversation.update_columns(additional_attributes: { 'campaign_touches' => [touch] }) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.new(connection, period: '30d').payload[:ads].first[:name]).to eq('Fale com a gente')
    end
  end
end
