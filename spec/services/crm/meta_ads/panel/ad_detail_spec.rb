require 'rails_helper'

# O anúncio por dentro (#1088, F3b): os mesmos números do cartão do painel, o porquê do veredito, o dia a dia
# e as propostas do anúncio. Data fixa: o período e o "por dia" dependem de hoje.
RSpec.describe Crm::MetaAds::Panel::AdDetail do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account)).first }
  let(:quote_stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 2, metadata: { 'funnel_stage_type' => 'opportunity' })
  end
  let(:capa) { '120254710362980416' }
  let(:now) { Time.zone.parse('2026-10-06T15:00:00-03:00') }

  def detail(ad_id, days: 7)
    described_class.new(connection, ad_id: ad_id, days: days).payload
  end

  def spend(ad_id, date, value, target: account, ad_account_id: connection.ad_account_id)
    Crm::MetaAdInsightDaily.create!(account: target, ad_account_id: ad_account_id, ad_id: ad_id, date: date, currency: 'BRL', spend: value,
                                    campaign_id: 'camp-1', adset_id: 'set-1', attribution_window: '7d_click', fetched_at: now)
  end

  def meta_object(id, type, name, **extra)
    Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: type, name: name, fetched_at: now, **extra)
  end

  def from_ad(ad_id, at: 1.day.ago, card: nil)
    conversation = create(:conversation, account: account)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                            certainty: 'ad', ad_id: ad_id, touched_at: at)
    if card
      Crm::Card.create!(account: account, pipeline: pipeline, stage: quote_stage, title: 'Cotação', currency: 'BRL',
                        primary_conversation: conversation, **card)
    end
    conversation
  end

  def sale(value)
    { status: :won, value_cents: (value * 100).to_i }
  end

  # Um anúncio com `conversations` conversas, `sales` delas vendidas, e o gasto do período num dia só.
  def ad_with(ad_id, conversations:, sales:, spent:)
    spend(ad_id, Date.new(2026, 10, 6), spent)
    sales.times { from_ad(ad_id, card: sale(100)) }
    (conversations - sales).times { from_ad(ad_id) }
  end

  it 'traz o anúncio com nome, campanha, conjunto, os números do cartão e o dia a dia com zeros' do
    travel_to(now) do
      meta_object(capa, 'ad', 'Capa (1080x1350)', campaign_id: 'camp-1', adset_id: 'set-1', preview_url: 'https://fb.me/p',
                                                  thumbnail_url: 'https://cdn/capa.jpg')
      meta_object('camp-1', 'campaign', 'Viagem EUA')
      meta_object('set-1', 'adset', 'Conjunto 60+')
      spend(capa, Date.new(2026, 10, 6), 100)
      spend(capa, Date.new(2026, 10, 2), 20.5)
      from_ad(capa, at: 1.day.ago)
      # 23h de 5/10 em São Paulo (fuso da conta de anúncios) já é 6/10 em UTC: conta no dia 5.
      from_ad(capa, at: Time.zone.parse('2026-10-06T02:00:00Z'))

      ad = detail(capa)

      expect(ad).to include(days: 7, from: Date.new(2026, 9, 30), to: Date.new(2026, 10, 6), currency: 'BRL', ad_id: capa,
                            name: 'Capa (1080x1350)', thumbnail_url: 'https://cdn/capa.jpg', preview_url: 'https://fb.me/p',
                            campaign_name: 'Viagem EUA', adset_name: 'Conjunto 60+', spend: 120.5, conversations: 2, quotes: 0,
                            sales: 0, sales_value: 0.0, cost_per_sale: nil, verdict: 'early', account_average_cost_per_sale: nil)
      expect(ad[:reason]).to eq(kind: 'early', missing_conversations: 18, difference: nil)
      expect(ad[:daily].size).to eq(7)
      expect(ad[:daily].reject { |day| day[:spend].zero? && day[:conversations].zero? }).to eq(
        [{ date: Date.new(2026, 10, 2), spend: 20.5, conversations: 0 },
         { date: Date.new(2026, 10, 5), spend: 0.0, conversations: 2 },
         { date: Date.new(2026, 10, 6), spend: 100.0, conversations: 0 }]
      )
    end
  end

  it 'campanha e conjunto saem do gasto quando o anúncio ainda não tem nome no cache' do
    travel_to(now) do
      meta_object('camp-1', 'campaign', 'Viagem EUA')
      spend(capa, Date.new(2026, 10, 6), 10)

      expect(detail(capa)).to include(name: nil, campaign_name: 'Viagem EUA', adset_name: nil, preview_url: nil)
    end
  end

  it 'lista as propostas: abertas primeiro pela espera mais antiga, depois as vendas' do
    travel_to(now) do
      lead_stage = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 1, metadata: { 'funnel_stage_type' => 'lead' })
      won = from_ad(capa, card: sale(622.64).merge(title: 'Venda'))
      recent = from_ad(capa, card: { title: 'Recente', value_cents: 50_000, last_message_at: 1.hour.ago })
      old = from_ad(capa, card: { title: 'Antiga', value_cents: 84_200, last_message_at: 4.days.ago })
      from_ad(capa, card: { title: 'Só lead', stage: lead_stage })

      list = detail(capa)[:quotes_list]

      expect(list.map { |quote| quote.slice(:title, :status, :value, :stage_name, :conversation_id) }).to eq(
        [{ title: 'Antiga', status: 'open', value: 842.0, stage_name: 'Proposta', conversation_id: old.id },
         { title: 'Recente', status: 'open', value: 500.0, stage_name: 'Proposta', conversation_id: recent.id },
         { title: 'Venda', status: 'won', value: 622.64, stage_name: 'Proposta', conversation_id: won.id }]
      )
      expect(list.first[:waiting_since]).to eq(4.days.ago)
      expect(list.first[:card_id]).to be_a(Integer)
    end
  end

  it 'o porquê sem base suficiente: sem venda depois de 20 conversas e sinal inicial com 1 ou 2 vendas' do
    travel_to(now) do
      ad_with('sem-venda', conversations: 20, sales: 0, spent: 200)
      ad_with('sinal', conversations: 20, sales: 1, spent: 150)

      expect(detail('sem-venda')).to include(verdict: 'review', reason: { kind: 'no_sales', missing_conversations: nil, difference: nil })
      expect(detail('sinal')).to include(verdict: 'signal', reason: { kind: 'signal', missing_conversations: nil, difference: nil })
    end
  end

  it 'o porquê com base suficiente compara o custo por venda com a média da conta, com a diferença em dinheiro' do
    travel_to(now) do
      ad_with('barato', conversations: 20, sales: 3, spent: 300) # 100 por venda
      ad_with('caro', conversations: 20, sales: 3, spent: 900)   # 300 por venda
      ad_with('na-media', conversations: 20, sales: 3, spent: 650) # 216,67 por venda; média 1850 / 9 = 205,56

      expect(detail('barato', days: 30)).to include(verdict: 'up', account_average_cost_per_sale: 205.56,
                                                    reason: { kind: 'below_average', missing_conversations: nil, difference: 105.56 })
      expect(detail('na-media', days: 30)).to include(verdict: 'keep',
                                                      reason: { kind: 'near_average', missing_conversations: nil, difference: 11.11 })
      expect(detail('caro', days: 30)).to include(verdict: 'review',
                                                  reason: { kind: 'above_average', missing_conversations: nil, difference: 94.44 })
    end
  end

  it 'anúncio de outra conta, fora do período ou sem id não aparece' do
    travel_to(now) do
      other = create(:account)
      spend('de-outra-conta', Date.new(2026, 10, 6), 50, target: other)
      spend('outra-conta-de-anuncios', Date.new(2026, 10, 6), 50, ad_account_id: '999')
      spend(capa, Date.new(2026, 9, 20), 80)

      expect(detail('de-outra-conta')).to be_nil
      expect(detail('outra-conta-de-anuncios')).to be_nil
      expect(detail(capa)).to be_nil
      expect(detail(capa, days: 30)).to include(spend: 80.0)
      expect(detail(nil)).to be_nil
    end
  end
end
