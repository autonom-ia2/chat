require 'rails_helper'

# Anúncio de clique para o Messenger e o Direct (#2521): o referral vira toque de campanha da conversa, igual ao do
# WhatsApp, e a ligação conversa → anúncio (Links::Linker) com origem `messenger` ou `instagram`.
RSpec.describe Crm::MetaAds::MessagingReferral do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:messenger) { Crm::MetaAds::MessagingReferral::MESSENGER_SOURCE }
  let(:ad_referral) do
    { 'source' => 'ADS', 'type' => 'OPEN_THREAD', 'ad_id' => '120200000000000001', 'ref' => 'promo',
      'ads_context_data' => { 'ad_title' => 'Seguro viagem', 'photo_url' => 'https://scontent.xx.fbcdn.net/foto.jpg' } }
  end

  def touches
    conversation.reload.additional_attributes['campaign_touches']
  end

  it 'grava o anúncio com o id, o título e o id do evento; link e loja não são anúncio' do
    expect(described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')).to be(true)

    expect(touches.sole).to include('source' => 'meta_ctm', 'source_id' => '120200000000000001', 'source_type' => 'ad',
                                    'headline' => 'Seguro viagem', 'media_type' => 'image', 'referral_id' => 'mid.1')
    expect(described_class.attribute!(conversation, { 'source' => 'SHORTLINK', 'ref' => 'x' }, source: messenger, event_id: 'mid.2'))
      .to be(false)
    expect(described_class.attribute!(conversation, ad_referral.except('ad_id'), source: messenger, event_id: 'mid.3')).to be(false)
    expect(described_class.attribute!(conversation, nil, source: messenger, event_id: 'mid.4')).to be(false)
  end

  it 'dois cliques no mesmo anúncio são dois toques; a reentrega do mesmo evento não duplica' do
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.2')

    expect(touches.pluck('referral_id')).to eq(%w[mid.1 mid.2])
  end

  it 'a foto do anúncio vai para o job da foto, como no clique para o WhatsApp' do
    allow(Crm::MetaAds::ReferralImageJob).to receive(:enqueue_for)

    described_class.attribute!(conversation, ad_referral, source: Crm::MetaAds::MessagingReferral::INSTAGRAM_SOURCE, event_id: 'mid.1')

    expect(Crm::MetaAds::ReferralImageJob).to have_received(:enqueue_for)
      .with(conversation, hash_including('source' => 'meta_ctd'), hash_including(image_url: 'https://scontent.xx.fbcdn.net/foto.jpg'))
  end

  it 'evento só de referral vai para a conversa mais recente do contato na caixa; contato desconhecido não grava' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, created_at: 2.days.ago)
    latest = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)

    expect(described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(true)
    expect(latest.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
    expect(described_class.attribute_to_latest!(inbox, 'psid-2', ad_referral, source: messenger, event_id: 'psid-2:1700')).to be(false)
  end

  # A próxima mensagem de conversa encerrada abre conversa nova sem o referral: o clique vai para ela, não para a velha.
  it 'evento só de referral com a conversa encerrada fica guardado e vai para a próxima conversa' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    old = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)

    expect(described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(false)
    expect(old.reload.additional_attributes).not_to have_key('campaign_touches')

    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
    expect(described_class.attribute_message!(fresh, nil, source: messenger, event_id: 'mid.9', new_conversation: true)).to be(true)
    expect(fresh.reload.additional_attributes['campaign_touches'].sole).to include('source' => 'meta_ctm', 'referral_id' => 'psid-1:1700')
    expect(described_class.attribute_pending!(fresh)).to be(false)
  end

  it 'mensagem com referral que não é anúncio (link m.me) usa o clique guardado' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)
    described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')
    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)

    link = { 'source' => 'SHORTLINK', 'ref' => 'x' }
    described_class.attribute_message!(fresh, link, source: messenger, event_id: 'mid.9', new_conversation: true)

    expect(fresh.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
  end

  it 'dois cliques guardados valem os dois; mensagem em conversa que já existia não lê os guardados' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)
    other_ad = ad_referral.merge('ad_id' => '120200000000000002')
    described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')
    described_class.attribute_to_latest!(inbox, 'psid-1', other_ad, source: messenger, event_id: 'psid-1:1701')
    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)

    expect(described_class.attribute_message!(fresh, nil, source: messenger, event_id: 'mid.8', new_conversation: false)).to be(false)
    expect(described_class.attribute_message!(fresh, nil, source: messenger, event_id: 'mid.9', new_conversation: true)).to be(true)

    expect(fresh.reload.additional_attributes['campaign_touches'].pluck('source_id', 'referral_id'))
      .to eq([%w[120200000000000001 psid-1:1700], %w[120200000000000002 psid-1:1701]])
  end

  it 'o clique guardado não leva o link assinado da foto' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)

    described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')

    guardado = Redis::Alfred.lrange(described_class.pending_key(contact_inbox.id))
    expect(guardado.sole).to include('Seguro viagem')
    expect(guardado.sole).not_to include('fbcdn')
  end

  # Página que é caixa de duas contas: a mensagem chega nas duas, e o anúncio vai só para a conta que o conhece.
  it 'Página de duas contas: o anúncio vai só para a conversa da conta que o conhece' do
    page = create(:channel_facebook_page, account: account)
    other_page = create(:channel_facebook_page, page_id: page.page_id, account: create(:account))
    mine = create(:conversation, account: account, inbox: page.inbox)
    theirs = create(:conversation, account: other_page.account, inbox: other_page.inbox)
    Crm::MetaAdObject.create!(account: account, meta_object_id: '120200000000000001', object_type: 'ad', fetched_at: Time.current)

    expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.1')).to be(true)
    expect(described_class.attribute!(theirs, ad_referral, source: messenger, event_id: 'mid.1')).to be(false)
  end

  it 'caixa que trava numa conversa só grava o clique na conversa encerrada, que reabre' do
    inbox = conversation.inbox
    inbox.update!(lock_to_single_conversation: true)
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    old = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)

    expect(described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(true)
    expect(old.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
  end

  it 'o Linker liga a conversa ao anúncio com a origem do canal' do
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    other = create(:conversation, account: account)
    described_class.attribute!(other, ad_referral, source: Crm::MetaAds::MessagingReferral::INSTAGRAM_SOURCE, event_id: 'mid.9')

    [conversation, other].each { |item| Crm::MetaAds::Links::Linker.new(item.reload).perform }

    expect(Crm::MetaAdLink.where(account: account).pluck(:conversation_id, :origin, :ad_id, :certainty, :touch_key)).to contain_exactly(
      [conversation.id, 'messenger', '120200000000000001', 'ad', 'mid.1'],
      [other.id, 'instagram', '120200000000000001', 'ad', 'mid.9']
    )
  end
end
