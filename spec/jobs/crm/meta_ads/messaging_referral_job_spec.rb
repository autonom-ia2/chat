require 'rails_helper'

# Evento só de referral (#2521): o anúncio vai para a conversa mais recente do contato em cada caixa da Página.
RSpec.describe Crm::MetaAds::MessagingReferralJob do
  let(:referral) { { 'source' => 'ADS', 'ad_id' => '120200000000000001' } }

  def conversation_in(inbox, source_id)
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: source_id)
    create(:conversation, account: inbox.account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
  end

  it 'Messenger: grava com o id do evento pelo remetente e a hora; Página de duas contas, só na que conhece o anúncio' do
    first = create(:channel_facebook_page, page_id: 'page-1')
    second = create(:channel_facebook_page, page_id: 'page-1', account: create(:account))
    mine, theirs = [first, second].map { |page| conversation_in(page.inbox, 'psid-1') }
    Crm::MetaAdObject.create!(account: mine.account, meta_object_id: '120200000000000001', object_type: 'ad', fetched_at: Time.current)

    described_class.perform_now('messenger', 'page-1', 'psid-1', referral, '1700000000')

    expect(mine.reload.additional_attributes['campaign_touches'].sole).to include('source' => 'meta_ctm', 'referral_id' => 'psid-1:1700000000')
    expect(theirs.reload.additional_attributes).not_to have_key('campaign_touches')
  end

  it 'enfileira só o anúncio, sem os links assinados; referral que não é anúncio não enfileira' do
    context = { 'ad_title' => 'Promo', 'photo_url' => 'https://x.fbcdn.net/p.jpg' }
    messaging = { 'sender' => { 'id' => 'psid-1' }, 'recipient' => { 'id' => 'page-1' }, 'timestamp' => 1_700_000_000,
                  'referral' => { 'source' => 'ADS', 'ad_id' => '120200000001202', 'ads_context_data' => context } }

    expect { described_class.enqueue_for('messenger', messaging) }.to have_enqueued_job(described_class)
      .with('messenger', 'page-1', 'psid-1', { 'source' => 'ADS', 'ad_id' => '120200000001202', 'ads_context_data' => { 'ad_title' => 'Promo' },
                                               'media_type' => 'image', 'clicked_at' => '1700000000' }, '1700000000')
    expect { described_class.enqueue_for('messenger', messaging.merge('referral' => { 'source' => 'SHORTLINK' })) }
      .not_to have_enqueued_job(described_class)
  end

  it 'Instagram: acha a caixa pelo id da conta; caixa desconhecida não faz nada' do
    channel = create(:channel_instagram, instagram_id: 'ig-business-1')
    conversation = conversation_in(channel.inbox, 'igsid-1')

    described_class.perform_now('instagram', 'ig-business-1', 'igsid-1', referral, '1700000000')
    described_class.perform_now('instagram', 'ig-desconhecido', 'igsid-1', referral, '1700000001')

    expect(conversation.reload.additional_attributes['campaign_touches'].sole).to include('source' => 'meta_ctd')
  end

  # #2781: o mesmo Instagram em duas contas. Cada conta recebe pelo seu canal: o do login do Instagram, ou a Página.
  it 'Instagram em duas contas: uma caixa por conta, login do Instagram antes da Página' do
    direct = create(:channel_instagram, instagram_id: 'ig-shared')
    create(:channel_instagram_fb_page, account: direct.account, instagram_id: 'ig-shared')
    page = create(:channel_instagram_fb_page, instagram_id: 'ig-shared')
    create(:inbox, channel: page, account: page.account)

    expect(described_class.inboxes_for('instagram', 'ig-shared')).to eq([direct.inbox, page.inbox])
  end

  it 'a foto do anúncio vai direto para o job da foto, só quando a Página é de uma conta só' do
    page = create(:channel_facebook_page, page_id: 'page-1')
    allow(Crm::MetaAds::SemLogin).to receive(:enabled?).and_return(true)
    messaging = { 'sender' => { 'id' => 'psid-1' }, 'recipient' => { 'id' => 'page-1' }, 'timestamp' => 1_700_000_000,
                  'referral' => { 'source' => 'ADS', 'ad_id' => '120200000001202', 'ads_context_data' => { 'photo_url' => 'https://x.fbcdn.net/p.jpg' } } }

    expect { described_class.enqueue_for('messenger', messaging) }
      .to have_enqueued_job(Crm::MetaAds::ReferralImageJob).with(page.inbox.account_id, '120200000001202', 'https://x.fbcdn.net/p.jpg')

    create(:channel_facebook_page, page_id: 'page-1')
    expect { described_class.enqueue_for('messenger', messaging) }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end

  it 'sem a hora do evento não grava (todo clique do contato teria o mesmo id)' do
    page = create(:channel_facebook_page, page_id: 'page-1')
    conversation = conversation_in(page.inbox, 'psid-1')

    described_class.perform_now('messenger', 'page-1', 'psid-1', referral, '')

    expect(conversation.reload.additional_attributes).not_to have_key('campaign_touches')
  end
end
