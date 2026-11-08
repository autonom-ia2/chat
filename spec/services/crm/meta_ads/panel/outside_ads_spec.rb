require 'rails_helper'

# Quais anúncios ficam fora dos que trazem conversa (#2054, #2521, #2621). A conversa pelo nosso clique sempre puxa o
# anúncio para a conversa; a que só a Meta contou pesa apenas quando o destino do conjunto não está dito.
RSpec.describe Crm::MetaAds::Panel::OutsideAds do
  let(:account) { create(:account) }
  let(:now) { Time.zone.parse('2026-11-06T12:00:00-03:00') }

  def adset(id, destination, goal = nil)
    Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'adset', name: id, destination_type: destination,
                              optimization_goal: goal, fetched_at: now)
  end

  def spend(ad_id, adset_id, conversations_started: 0)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: 'act', ad_id: ad_id, adset_id: adset_id, date: now.to_date,
                                    currency: 'BRL', spend: 10, attribution_window: '7d_click', fetched_at: now,
                                    conversations_started: conversations_started)
  end

  def link(ad_id, origin:)
    Crm::MetaAdLink.create!(account: account, conversation: create(:conversation, account: account), touch_key: SecureRandom.hex(4),
                            origin: origin, certainty: 'ad', ad_id: ad_id, touched_at: now)
  end

  it 'separa pelo destino dito, pelo objetivo e pelo clique' do
    adset('set-perfil', 'INSTAGRAM_PROFILE', 'PROFILE_VISIT')
    adset('set-site', 'WEBSITE', 'LINK_CLICKS')
    adset('set-alcance', 'UNDEFINED', 'REACH')
    spend('perfil-contado-pela-meta', 'set-perfil', conversations_started: 1)
    spend('site-com-clique', 'set-site')
    spend('alcance-contado-pela-meta', 'set-alcance', conversations_started: 1)
    spend('alcance', 'set-alcance')
    link('site-com-clique', origin: 'whatsapp')

    outside = described_class.new(account.id, ad_ids: %w[perfil-contado-pela-meta site-com-clique alcance-contado-pela-meta alcance])

    expect(outside.ids).to contain_exactly('perfil-contado-pela-meta', 'alcance')
  end

  it 'a conversa do privado de um comentário de anúncio de fora não conta como conversa de anúncio' do
    adset('set-perfil', 'INSTAGRAM_PROFILE', 'PROFILE_VISIT')
    spend('perfil', 'set-perfil', conversations_started: 1)
    comment = link('perfil', origin: Crm::MetaAds::Links::CommentTouch::ORIGIN)
    clicked = link('outro', origin: 'whatsapp')

    counted = described_class.counted_links(account.id, Crm::MetaAdLink.where(account_id: account.id))

    expect(counted).to contain_exactly(clicked)
    expect(counted).not_to include(comment)
  end
end
