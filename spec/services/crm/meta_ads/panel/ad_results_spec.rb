require 'rails_helper'

# #2521: o que a Meta mede em cada anúncio no período, somado dos dias.
RSpec.describe Crm::MetaAds::Panel::AdResults do
  let(:account) { create(:account) }

  def day(ad_id, date, actions, **metrics)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: '1', ad_id: ad_id, date: date, spend: 1, attribution_window: '7d_click',
                                    fetched_at: Time.current, actions: actions, **metrics)
  end

  it 'soma os dias, prefere o número da janela fixa e ignora ações que não mostra' do
    day('a', Date.new(2026, 10, 5), [{ 'action_type' => 'lead', 'value' => '9', '7d_click' => '4' },
                                     { 'action_type' => 'comment', 'value' => '2' }, { 'action_type' => 'like', 'value' => '50' }],
        impressions: 100, link_clicks: 10)
    day('a', Date.new(2026, 10, 6), [{ 'action_type' => 'video_view', 'value' => '30' }, 'lixo', { 'action_type' => 'post_engagement' }],
        impressions: 50, link_clicks: 5)

    results = described_class.new(Crm::MetaAdInsightDaily.where(account: account))

    expect(results.for('a')).to eq(impressions: 150, link_clicks: 15, comments: 2, post_engagement: 0, video_views: 30, leads: 4)
    expect(results.for('sem-gasto')).to eq(described_class::EMPTY)
  end
end
