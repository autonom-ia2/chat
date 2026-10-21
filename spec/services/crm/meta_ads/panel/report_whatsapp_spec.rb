require 'rails_helper'

# Anúncios sem login (#1960): o painel sem conexão lê os toques gravados na conversa e conta o que virou no CRM.
RSpec.describe Crm::MetaAds::Panel::Report do
  let(:account) { create(:account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account)).first }
  let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 1) }
  let(:auto) { '120254710362980416' }
  let(:fale) { '120254710382780416' }
  let(:now) { Time.zone.parse('2026-10-20T15:00:00-03:00') }

  def ad_click(ad_id, at, headline: 'Seguro auto sem complicação')
    { 'source' => 'meta_ctwa', 'source_id' => ad_id, 'source_type' => 'ad', 'headline' => headline, 'ctwa_clid' => SecureRandom.hex(4),
      'touched_at' => at.utc.iso8601 }
  end

  def from_ad(*touches, status: nil, value: 0)
    conversation = create(:conversation, account: account)
    conversation.update_columns(additional_attributes: { 'campaign' => touches.first, 'campaign_touches' => touches }) # rubocop:disable Rails/SkipsModelValidations
    if status
      Crm::Card.create!(account: account, pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL', primary_conversation: conversation,
                        status: status, value_cents: (value * 100).to_i)
    end
    conversation
  end

  it 'conta conversas, em negociação, perdidos e compras por anúncio, com o título do clique como nome' do
    travel_to(now) do
      from_ad(ad_click(auto, 1.day.ago), status: :won, value: 400)
      from_ad(ad_click(auto, 2.days.ago), status: :open, value: 1200.5)
      from_ad(ad_click(auto, 3.days.ago), status: :lost)
      from_ad(ad_click(fale, 1.day.ago, headline: 'Fale com a gente'))
      from_ad(ad_click(fale, 40.days.ago, headline: 'Fale com a gente'), status: :won, value: 999) # fora dos 30 dias

      report = described_class.new(nil, days: 30, account: account).payload

      expect(report[:source]).to eq('whatsapp')
      expect(report).not_to have_key(:confidence)
      expect(report[:totals]).to include(conversations: 4, spend: nil, sales: 1, sales_value: 400.0, open: 1, open_value: 1200.5, lost: 1,
                                         cost_per_sale: nil, cost_per_conversation: nil, return_per_real: nil)
      expect(report[:ads].first).to include(spend: nil, cost_per_sale: nil, verdict: nil)
      expect(Crm::MetaAds::Panel::AdDetail.new(nil, ad_id: auto, period: '30d', account: account).payload).to include(reason: nil, spend: nil)
      expect(report[:ads].map { |ad| ad.slice(:ad_id, :name, :conversations, :sales, :open, :lost) }).to eq(
        [{ ad_id: auto, name: 'Seguro auto sem complicação', conversations: 3, sales: 1, open: 1, lost: 1 },
         { ad_id: fale, name: 'Fale com a gente', conversations: 1, sales: 0, open: 0, lost: 0 }]
      )
    end
  end

  it 'conta a conversa no anúncio do primeiro clique do período e ignora toque que não é de anúncio' do
    travel_to(now) do
      organic = { 'source' => 'meta_organic', 'source_id' => 'post-1', 'touched_at' => 5.days.ago.utc.iso8601 }
      from_ad(organic, ad_click(fale, 4.days.ago, headline: 'Fale com a gente'), ad_click(auto, 1.day.ago))
      from_ad(organic)

      report = described_class.new(nil, days: 30, account: account).payload

      expect(report[:totals][:conversations]).to eq(1)
      expect(report[:ads].map { |ad| [ad[:ad_id], ad[:conversations]] }).to eq([[fale, 1]])
    end
  end

  it 'mostra a foto guardada do anúncio e prefere o nome resolvido pela Meta' do
    travel_to(now) do
      from_ad(ad_click(auto, 1.day.ago))
      object = Crm::MetaAdObject.create!(account: account, meta_object_id: auto, object_type: 'ad', name: 'Capa (1080x1350)')
      object.image.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'anuncio.png', content_type: 'image/png')

      ad = described_class.new(nil, days: 30, account: account).payload[:ads].first

      expect(ad[:name]).to eq('Capa (1080x1350)')
      expect(ad[:image_url]).to start_with('/rails/active_storage/blobs/')
    end
  end

  it 'usa o fuso da conta para o período' do
    account.update!(custom_attributes: { 'timezone' => 'America/Manaus' })
    travel_to(now) do
      report = described_class.new(nil, days: 7, account: account)

      expect(report.zone.name).to eq('America/Manaus')
      expect(report.payload).to include(from: Date.new(2026, 10, 14), to: Date.new(2026, 10, 20))
    end
  end

  describe 'períodos (#2011)' do
    let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

    before { account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }

    it 'conta só o mês passado, fechado, no fuso da conta' do
      travel_to(now) do
        from_ad(ad_click(auto, zone.parse('2026-08-31T23:30:00')))
        setembro = from_ad(ad_click(auto, zone.parse('2026-09-01T00:10:00')), status: :won, value: 400)
        from_ad(ad_click(fale, zone.parse('2026-09-30T23:50:00'), headline: 'Fale com a gente'))
        from_ad(ad_click(auto, zone.parse('2026-10-01T00:05:00')))

        report = described_class.new(nil, period: 'last_month', account: account).payload

        expect(report).to include(period: 'last_month', days: 30, from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30), open: false)
        expect(report[:totals]).to include(conversations: 2, sales: 1)
        detail = Crm::MetaAds::Panel::AdDetail.new(nil, ad_id: auto, period: 'last_month', account: account).payload
        expect(detail[:people].map { |row| row[:conversation_id] }).to eq([setembro.id])
        expect(detail[:daily].size).to eq(30)
      end
    end

    it 'começa "desde o início" no dia do primeiro anúncio e conta tudo até hoje' do
      travel_to(now) do
        from_ad(ad_click(auto, zone.parse('2026-06-28T10:00:00')))
        from_ad(ad_click(fale, 1.day.ago, headline: 'Fale com a gente'))

        report = described_class.new(nil, period: 'all', account: account).payload

        expect(report).to include(period: 'all', from: Date.new(2026, 6, 28), to: Date.new(2026, 10, 20), open: true)
        expect(report[:totals][:conversations]).to eq(2)
      end
    end

    it 'lê o days antigo como antes e cai nos 30 dias com período desconhecido' do
      travel_to(now) do
        expect(described_class.new(nil, days: 7, account: account).payload).to include(period: '7d', days: 7)
        expect(described_class.new(nil, period: 'semana', account: account).payload).to include(period: '30d', days: 30)
      end
    end
  end

  describe 'o anúncio por dentro e as listas' do
    it 'traz as pessoas do anúncio com a situação e quem ficou sem resposta' do
      travel_to(now) do
        won = from_ad(ad_click(auto, 2.days.ago), status: :won, value: 400)
        waiting = from_ad(ad_click(auto, 1.day.ago))
        create(:message, account: account, conversation: waiting, inbox: waiting.inbox, message_type: :incoming, created_at: 1.day.ago)
        from_ad(ad_click(fale, 1.day.ago, headline: 'Fale com a gente'))

        detail = Crm::MetaAds::Panel::AdDetail.new(nil, ad_id: auto, period: '30d', account: account).payload
        slow = Crm::MetaAds::Panel::PathList.new(nil, step: 'slow_replies', period: '30d', account: account).payload

        expect(detail[:people].map { |row| [row[:conversation_id], row[:status]] }).to eq([[waiting.id, nil], [won.id, 'won']])
        expect(detail[:people].first[:answered]).to be(false)
        expect(slow[:items].map { |row| row[:conversation_id] }).to eq([waiting.id])
      end
    end
  end
end
