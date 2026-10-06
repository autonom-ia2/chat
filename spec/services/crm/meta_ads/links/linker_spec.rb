require 'rails_helper'

# Ligação conversa → anúncio (#1073, F2b, CA-2.5): o que é toque de anúncio da Meta e o quanto sabemos de cada um.
RSpec.describe Crm::MetaAds::Links::Linker do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}") }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let!(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120254710067060999' }
  let(:adset_id) { '120254710067060777' }
  let(:campaign_id) { '120254710067060416' }

  def ctwa_touch(**extra)
    { 'source' => 'meta_ctwa', 'source_id' => ad_id, 'source_type' => 'ad', 'ctwa_clid' => 'clid-1',
      'touched_at' => '2026-10-01T12:00:00Z' }.merge(extra.stringify_keys)
  end

  # O texto que a tela manda colar: campanha por ID, conjunto e anúncio por nome.
  def site_touch(**extra)
    { 'source' => 'meta_paid', 'source_id' => "site:ABC234:#{campaign_id}", 'source_type' => 'bridge', 'utm_source' => 'meta',
      'utm_campaign' => 'Viagem EUA', 'utm_term' => 'Conjunto 60+', 'utm_content' => 'Video 2', 'utm_id' => campaign_id,
      'touched_at' => '2026-10-02T12:00:00Z' }.merge(extra.stringify_keys)
  end

  def assign_touches(touches)
    conversation.update!(additional_attributes: { 'campaign' => touches.first, 'campaign_touches' => touches })
  end

  def cache_ad(id: ad_id, name: 'Video 2', campaign: campaign_id)
    Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'ad', name: name, campaign_id: campaign,
                              adset_id: adset_id, fetched_at: Time.current)
  end

  def link_for(key)
    Crm::MetaAdLink.find_by!(conversation: conversation, touch_key: key)
  end

  it 'clique para o WhatsApp: anúncio certo, conjunto e campanha do cache, primeiro toque' do
    cache_ad
    assign_touches([ctwa_touch])

    expect(described_class.new(conversation).perform).to eq(1)
    expect(link_for('clid-1')).to have_attributes(
      origin: 'whatsapp', certainty: 'ad', ad_id: ad_id, adset_id: adset_id, campaign_id: campaign_id,
      first_touch: true, ad_account_id: connection.ad_account_id, touched_at: Time.zone.parse('2026-10-01T12:00:00Z')
    )
  end

  it 'site com o texto colado: campanha por ID e anúncio achado pelo nome dentro dela' do
    cache_ad
    cache_ad(id: '777', name: 'Video 2', campaign: '999')
    assign_touches([site_touch])

    described_class.new(conversation).perform

    expect(link_for("site:ABC234:#{campaign_id}"))
      .to have_attributes(origin: 'site', certainty: 'ad_name', ad_id: ad_id, campaign_id: campaign_id, adset_id: adset_id)
  end

  it 'nome repetido na mesma campanha não chuta: fica só a campanha' do
    cache_ad
    cache_ad(id: '777', name: 'Video 2')
    assign_touches([site_touch])

    described_class.new(conversation).perform

    expect(link_for("site:ABC234:#{campaign_id}")).to have_attributes(certainty: 'campaign', ad_id: nil, campaign_id: campaign_id)
  end

  it 'site com ID do anúncio no texto: anúncio certo' do
    assign_touches([site_touch('utm_content' => ad_id)])

    described_class.new(conversation).perform

    expect(link_for("site:ABC234:#{campaign_id}")).to have_attributes(certainty: 'ad', ad_id: ad_id)
  end

  it 'site só com o fbclid da Meta: veio da Meta, sem saber o anúncio' do
    touch = { 'source' => 'tracked_link', 'source_id' => 'site:ABC234:none', 'fbclid' => 'fb-1', 'touched_at' => '2026-10-02T12:00:00Z' }
    assign_touches([touch])

    described_class.new(conversation).perform

    expect(link_for('site:ABC234:none')).to have_attributes(origin: 'site', certainty: 'unknown', ad_id: nil, campaign_id: nil)
  end

  it 'deixa de fora o que não é anúncio da Meta (QR, Google, site sem sinal da Meta)' do
    qr = { 'source' => 'tracked_link', 'source_id' => 'click:TOKEN', 'touched_at' => '2026-10-02T12:00:00Z' }
    google = { 'source' => 'tracked_link', 'source_id' => 'site:ABC234:none', 'gclid' => 'g-1', 'touched_at' => '2026-10-02T12:00:00Z' }
    assign_touches([qr, google])

    expect(described_class.new(conversation).perform).to eq(0)
    expect(Crm::MetaAdLink.count).to eq(0)
  end

  it 'regravar o mesmo toque atualiza, nunca duplica; só o primeiro toque é a origem' do
    assign_touches([ctwa_touch, ctwa_touch('ctwa_clid' => 'clid-2', 'touched_at' => '2026-10-03T12:00:00Z')])
    described_class.new(conversation).perform
    cache_ad

    described_class.new(conversation.reload).perform

    expect(Crm::MetaAdLink.where(conversation: conversation).order(:touched_at).pluck(:touch_key, :first_touch, :campaign_id))
      .to eq([['clid-1', true, campaign_id], ['clid-2', false, campaign_id]])
  end
end
