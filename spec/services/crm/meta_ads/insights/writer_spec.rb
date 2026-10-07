require 'rails_helper'

# Gravação das linhas da Insights API (#1073): upsert por anúncio e dia, janela gravada, nomes no cache.
RSpec.describe Crm::MetaAds::Insights::Writer do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:writer) { described_class.new(connection) }

  def row(**overrides)
    meta_insights_row(**overrides).deep_stringify_keys
  end

  it 'grava uma linha por anúncio e dia com gasto, contagens, conversas e a janela de 7 dias por clique' do
    expect(writer.ads!([row])).to eq(1)

    saved = Crm::MetaAdInsightDaily.sole
    expect(saved).to have_attributes(
      account_id: account.id, ad_account_id: connection.ad_account_id, ad_id: '120254710067060999',
      adset_id: '120254710067060777', campaign_id: '120254710067060416', date: Date.new(2026, 10, 6), currency: 'BRL',
      spend: BigDecimal('42.5'), impressions: 1500, reach: 1200, frequency: BigDecimal('1.25'), link_clicks: 40,
      conversations_started: 3, attribution_window: '7d_click'
    )
    expect(saved.actions.first['action_type']).to eq('onsite_conversion.messaging_conversation_started_7d')
  end

  it 'reler o mesmo dia sobrescreve, nunca duplica (CA-2.4)' do
    writer.ads!([row(spend: '10.00')])
    described_class.new(connection).ads!([row(spend: '12.30', conversations: '5')])

    expect(Crm::MetaAdInsightDaily.count).to eq(1)
    expect(Crm::MetaAdInsightDaily.sole).to have_attributes(spend: BigDecimal('12.3'), conversations_started: 5)
  end

  it 'guarda os nomes no cache sem apagar a prévia e a miniatura do anúncio' do
    Crm::MetaAdObject.create!(account: account, meta_object_id: '120254710067060999', object_type: 'ad', name: 'Antigo',
                              preview_url: 'https://fb.me/adspreview/abc', fetched_at: 10.days.ago)

    writer.ads!([row, row(date: '2026-10-05')])

    ad = Crm::MetaAdObject.find_by(meta_object_id: '120254710067060999')
    expect(ad).to have_attributes(name: 'Video 2', preview_url: 'https://fb.me/adspreview/abc', campaign_id: '120254710067060416')
    expect(ad.fetched_at).to be > 1.minute.ago
    expect(Crm::MetaAdObject.where(account: account).pluck(:object_type).sort).to eq(%w[ad adset campaign])
  end

  it 'sem a ação de conversa conta zero; linha sem anúncio ou sem data fica de fora' do
    rows = [row(actions: [{ action_type: 'link_click', value: '4' }]), row(ad_id: nil), row(date_start: 'ontem', ad_id: '9')]

    expect(writer.ads!(rows)).to eq(1)
    expect(Crm::MetaAdInsightDaily.sole.conversations_started).to eq(0)
  end

  it 'grava a frequência da janela por anúncio, com o date_stop da Meta como fim; linha sem anúncio ou sem fim fica de fora' do
    rows = [
      { 'ad_id' => '1', 'adset_id' => '10', 'impressions' => '4600', 'reach' => '1000', 'frequency' => '4.6', 'date_stop' => '2026-10-05' },
      { 'ad_id' => nil, 'date_stop' => '2026-10-05' },
      { 'ad_id' => '2', 'date_stop' => nil }
    ]

    expect(writer.frequency_windows!(rows, window_days: 7)).to eq(1)
    expect(described_class.new(connection).frequency_windows!([rows.first.merge('frequency' => '4.8')], window_days: 7)).to eq(1)

    expect(Crm::MetaAdFrequencyWindow.sole).to have_attributes(
      account_id: account.id, ad_account_id: connection.ad_account_id, ad_id: '1', adset_id: '10', window_days: 7,
      date_end: Date.new(2026, 10, 5), impressions: 4600, reach: 1000, frequency: BigDecimal('4.8')
    )
  end

  it 'grava posicionamento por plataforma e posição' do
    rows = [
      row(publisher_platform: 'instagram', platform_position: 'instagram_reels', spend: '20.00'),
      row(publisher_platform: 'facebook', platform_position: 'feed', spend: '22.50'),
      row(publisher_platform: nil, platform_position: 'feed')
    ]

    expect(writer.placements!(rows)).to eq(2)
    expect(Crm::MetaAdPlacementDaily.order(:spend).pluck(:publisher_platform, :platform_position, :spend))
      .to eq([['instagram', 'instagram_reels', BigDecimal(20)], ['facebook', 'feed', BigDecimal('22.5')]])
  end
end
