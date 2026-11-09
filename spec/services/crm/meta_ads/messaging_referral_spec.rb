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

  it 'dois cliques no mesmo anúncio em momentos diferentes são dois toques; a reentrega do mesmo evento não duplica' do
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    travel_to(2.minutes.from_now) do
      described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.2')
    end

    expect(touches.pluck('referral_id')).to eq(%w[mid.1 mid.2])
  end

  # #2607: a Meta manda o clique no evento solto e, segundos depois, na mensagem, cada um com o seu id.
  it 'o mesmo clique no evento e na mensagem é um toque só, o do evento' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    open_one = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)

    expect(described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(true)
    travel_to(5.seconds.from_now) do
      expect(described_class.attribute_message!(open_one, ad_referral, source: messenger, event_id: 'mid.1', new_conversation: false))
        .to be(false)
    end

    expect(open_one.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
  end

  it 'na ordem inversa também: a mensagem grava e o evento do mesmo clique não' do
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    travel_to(5.seconds.from_now) do
      expect(described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(false)
    end

    expect(touches.pluck('referral_id')).to eq(%w[mid.1])
  end

  it 'conversa encerrada: o clique guardado do evento entra na conversa nova e a mensagem do mesmo clique não repete' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)

    expect(described_class.attribute_to_latest!(inbox, 'psid-1', ad_referral, source: messenger, event_id: 'psid-1:1700')).to be(false)
    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
    travel_to(5.seconds.from_now) do
      expect(described_class.attribute_message!(fresh, ad_referral, source: messenger, event_id: 'mid.1', new_conversation: true)).to be(true)
    end

    expect(fresh.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
    expect(described_class.attribute_pending!(fresh)).to be(false)
  end

  # A hora que vale é a do clique que a Meta manda (segundos no evento, milissegundos na mensagem), não a do processamento.
  def clicked(timestamp) = described_class.with_click_time(ad_referral, timestamp)

  it 'a janela do mesmo clique, pela hora da Meta: 59 s junta, 61 s separa' do
    described_class.attribute!(conversation, clicked('1700000000'), source: messenger, event_id: 'psid-1:1700000000')
    expect(described_class.attribute!(conversation, clicked(1_700_000_059_000), source: messenger, event_id: 'mid.1')).to be(false)
    expect(described_class.attribute!(conversation, clicked(1_700_000_061_000), source: messenger, event_id: 'mid.2')).to be(true)

    expect(touches.pluck('referral_id', 'touched_at'))
      .to eq([%w[psid-1:1700000000 2023-11-14T22:13:20Z], %w[mid.2 2023-11-14T22:14:21Z]])
  end

  it 'fila atrasada ou nova tentativa não separam o mesmo clique: vale a hora da Meta' do
    described_class.attribute!(conversation, clicked('1700000000'), source: messenger, event_id: 'psid-1:1700000000')
    travel_to(10.minutes.from_now) do
      expect(described_class.attribute!(conversation, clicked(1_700_000_004_000), source: messenger, event_id: 'mid.1')).to be(false)
    end

    expect(touches.pluck('referral_id')).to eq(%w[psid-1:1700000000])
  end

  it 'a hora do clique segue no referral enxuto da fila e do Redis' do
    expect(described_class.slim(clicked('1700000000'))).to include('clicked_at' => '1700000000')
    expect(described_class.slim(ad_referral)).not_to have_key('clicked_at')
  end

  it 'dois cliques guardados no mesmo anúncio em horas diferentes continuam dois toques na conversa nova' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, status: :resolved)
    described_class.attribute_to_latest!(inbox, 'psid-1', clicked('1700000000'), source: messenger, event_id: 'psid-1:1700000000')
    described_class.attribute_to_latest!(inbox, 'psid-1', clicked('1700018000'), source: messenger, event_id: 'psid-1:1700018000')

    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
    expect(described_class.attribute_message!(fresh, clicked(1_700_018_004_000), source: messenger, event_id: 'mid.1', new_conversation: true))
      .to be(true)

    expect(fresh.reload.additional_attributes['campaign_touches'].pluck('referral_id')).to eq(%w[psid-1:1700000000 psid-1:1700018000])
  end

  it 'hora da Meta que não é número fica de fora: vale a hora de agora' do
    freeze_time do
      described_class.attribute!(conversation, clicked('amanhã'), source: messenger, event_id: 'mid.1')

      expect(touches.sole['touched_at']).to eq(Time.current.utc.iso8601)
    end
  end

  it 'o toque do WhatsApp com o mesmo anúncio no mesmo instante continua sendo outro toque' do
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    Ctwa::CampaignBuilder.attribute!(conversation, { 'source_type' => 'ad', 'source_id' => '120200000000000001', 'ctwa_clid' => 'clid-1' })

    expect(touches.pluck('source', 'source_id')).to eq([%w[meta_ctm 120200000000000001], %w[meta_ctwa 120200000000000001]])
  end

  it 'outro anúncio, ou o mesmo anúncio no outro canal, no mesmo instante é outro toque' do
    other_ad = ad_referral.merge('ad_id' => '120200000000000002')
    described_class.attribute!(conversation, ad_referral, source: messenger, event_id: 'mid.1')
    described_class.attribute!(conversation, other_ad, source: messenger, event_id: 'mid.2')
    described_class.attribute!(conversation, ad_referral, source: Crm::MetaAds::MessagingReferral::INSTAGRAM_SOURCE, event_id: 'mid.3')

    expect(touches.pluck('source', 'source_id'))
      .to eq([%w[meta_ctm 120200000000000001], %w[meta_ctm 120200000000000002], %w[meta_ctd 120200000000000001]])
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
  it 'Página de duas contas: o anúncio vai só para a conta que o conhece' do
    page = create(:channel_facebook_page)
    other_page = create(:channel_facebook_page, page_id: page.page_id)
    mine = create(:conversation, account: page.inbox.account, inbox: page.inbox)
    theirs = create(:conversation, account: other_page.inbox.account, inbox: other_page.inbox)
    Crm::MetaAdObject.create!(account: mine.account, meta_object_id: '120200000000000001', object_type: 'ad', fetched_at: Time.current)

    expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.1')).to be(true)
    expect(described_class.attribute!(theirs, ad_referral, source: messenger, event_id: 'mid.1')).to be(false)
  end

  # #2781: o mesmo Instagram em duas contas. O clique vai só para a conta que conhece o anúncio, como na Página.
  it 'Instagram de duas contas: o anúncio vai só para a conta que o conhece' do
    instagram = Crm::MetaAds::MessagingReferral::INSTAGRAM_SOURCE
    first = create(:channel_instagram, instagram_id: 'ig-shared')
    second = create(:channel_instagram, instagram_id: 'ig-shared')
    mine = create(:conversation, account: first.account, inbox: first.inbox)
    theirs = create(:conversation, account: second.account, inbox: second.inbox)
    Crm::MetaAdObject.create!(account: mine.account, meta_object_id: '120200000000000001', object_type: 'ad', fetched_at: Time.current)

    expect(described_class.attribute!(mine, ad_referral, source: instagram, event_id: 'mid.1')).to be(true)
    expect(described_class.attribute!(theirs, ad_referral, source: instagram, event_id: 'mid.1')).to be(false)
  end

  # Anúncio novo, que nenhuma conta da Página conhece: a Graph diz de qual conta de anúncios ele é; sem conexão, não grava.
  it 'Página de duas contas e anúncio novo: grava só na conta cuja conta de anúncios é a do anúncio' do
    page = create(:channel_facebook_page)
    other_page = create(:channel_facebook_page, page_id: page.page_id)
    third_page = create(:channel_facebook_page, page_id: page.page_id)
    mine, theirs, without = [page, other_page, third_page].map do |channel|
      create(:conversation, account: channel.inbox.account, inbox: channel.inbox)
    end
    create_meta_ads_insights_connection(mine.account, ad_account_id: '700000')
    create_meta_ads_insights_connection(theirs.account, ad_account_id: '700001')
    stub_request(:get, %r{graph\.facebook\.com/.*/120200000000000001\?})
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { id: '120200000000000001', account_id: '700000' }.to_json)

    expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.1')).to be(true)
    expect(described_class.attribute!(theirs, ad_referral, source: messenger, event_id: 'mid.1')).to be(false)
    expect(described_class.attribute!(without, ad_referral, source: messenger, event_id: 'mid.1')).to be(false)
  end

  it 'dono do anúncio: a falha passageira da Graph não fica guardada, a resposta definitiva fica' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    page = create(:channel_facebook_page)
    create(:channel_facebook_page, page_id: page.page_id)
    mine = create(:conversation, account: page.inbox.account, inbox: page.inbox)
    create_meta_ads_insights_connection(mine.account, ad_account_id: '700000')
    graph = stub_request(:get, %r{graph\.facebook\.com/.*/120200000000000001\?})
            .to_return({ status: 503, body: '' },
                       { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { account_id: '700000' }.to_json })

    expect { described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.1') }
      .to raise_error(described_class::OwnerUnavailable)
    expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.2')).to be(true)
    travel_to(2.minutes.from_now) do
      expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: 'mid.3')).to be(true)
    end
    expect(graph).to have_been_requested.twice
  end

  it 'dono do anúncio: recusa do token (190) não fica guardada; anúncio de outra conta (100) fica' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    page = create(:channel_facebook_page)
    create(:channel_facebook_page, page_id: page.page_id)
    mine = create(:conversation, account: page.inbox.account, inbox: page.inbox)
    create_meta_ads_insights_connection(mine.account, ad_account_id: '700000')
    erro = ->(code) { { status: 400, headers: { 'Content-Type' => 'application/json' }, body: { error: { code: code } }.to_json } }
    graph = stub_request(:get, %r{graph\.facebook\.com/.*/120200000000000001\?}).to_return(erro.call(190), erro.call(100))

    3.times { |index| expect(described_class.attribute!(mine, ad_referral, source: messenger, event_id: "mid.#{index}")).to be(false) }
    expect(graph).to have_been_requested.twice
  end

  it 'ad_id que não é id da Meta (só dígitos, 6 a 30) não é anúncio: não vai para a Graph, o log nem a fila' do
    ['../me', '12345', '1202000000000a1', '1' * 31].each do |ad_id|
      referral = ad_referral.merge('ad_id' => ad_id)
      expect(described_class.for_campaign(referral, source: messenger, event_id: 'mid.1')).to be_nil
      expect(described_class.slim(referral)).to be_nil
    end
  end

  it 'no caminho da mensagem (dentro da trava), o dono pela Graph vai para o job, que grava fora da trava' do
    page = create(:channel_facebook_page)
    create(:channel_facebook_page, page_id: page.page_id)
    mine = create(:conversation, account: page.inbox.account, inbox: page.inbox)
    create_meta_ads_insights_connection(mine.account, ad_account_id: '700000')
    graph = stub_request(:get, %r{graph\.facebook\.com/.*/120200000000000001\?})
            .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { account_id: '700000' }.to_json)

    expect do
      expect(described_class.attribute_message!(mine, ad_referral, source: messenger, event_id: 'mid.1', new_conversation: true)).to be(false)
    end.to have_enqueued_job(Crm::MetaAds::MessagingReferralOwnerJob).with(mine.id, described_class.slim(ad_referral), messenger, 'mid.1')
    expect(graph).not_to have_been_requested

    perform_enqueued_jobs(only: Crm::MetaAds::MessagingReferralOwnerJob)
    expect(mine.reload.additional_attributes['campaign_touches'].sole).to include('source_id' => '120200000000000001', 'referral_id' => 'mid.1')
  end

  it 'o job do dono tenta de novo quando a Graph não responde de vez' do
    page = create(:channel_facebook_page)
    create(:channel_facebook_page, page_id: page.page_id)
    mine = create(:conversation, account: page.inbox.account, inbox: page.inbox)
    create_meta_ads_insights_connection(mine.account, ad_account_id: '700000')
    stub_request(:get, %r{graph\.facebook\.com/.*/120200000000000001\?}).to_return(status: 503, body: '')

    expect do
      Crm::MetaAds::MessagingReferralOwnerJob.perform_now(mine.id, described_class.slim(ad_referral), messenger, 'mid.1')
    end.to have_enqueued_job(Crm::MetaAds::MessagingReferralOwnerJob)
    expect(mine.reload.additional_attributes['campaign_touches']).to be_blank
  end

  it 'um clique guardado com defeito não leva os outros' do
    inbox = conversation.inbox
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: 'psid-1')
    fresh = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
    Redis::Alfred.with do |conn|
      conn.rpush(described_class.pending_key(contact_inbox.id), 'não é json')
      conn.rpush(described_class.pending_key(contact_inbox.id),
                 { referral: described_class.slim(ad_referral), source: messenger, event_id: 'psid-1:1700' }.to_json)
    end

    expect(described_class.attribute_pending!(fresh)).to be(true)
    expect(fresh.reload.additional_attributes['campaign_touches'].sole).to include('referral_id' => 'psid-1:1700')
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
