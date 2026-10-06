require 'rails_helper'

# Nomes da Meta nos toques da conversa (#1034): Crm::MetaAds::EnrichTouchesJob + TouchEnricher.
RSpec.describe Crm::MetaAds::EnrichTouchesJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}") }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:ad_id) { '120254710067060999' }
  let(:adset_id) { '120254710067060777' }
  let(:campaign_id) { '120254710067060416' }
  let(:ctwa_touch) do
    { 'source' => 'meta_ctwa', 'source_id' => ad_id, 'source_type' => 'ad', 'headline' => 'Fale conosco',
      'ctwa_clid' => 'clid-1', 'touched_at' => '2026-10-01T12:00:00Z' }
  end
  let(:site_touch) do
    { 'source' => 'meta_paid', 'source_id' => "site:ABC234:#{campaign_id}", 'source_type' => 'bridge',
      'headline' => "LP Seguro · #{campaign_id}", 'source_url' => 'https://exemplo.com.br/lp', 'utm_source' => 'meta',
      'utm_medium' => 'paid', 'utm_campaign' => campaign_id, 'utm_term' => adset_id, 'utm_content' => ad_id,
      'utm_id' => campaign_id, 'fbclid' => 'fb-1', 'touched_at' => '2026-10-02T12:00:00Z' }
  end

  def set_touches(touches, origin: touches.first, extra: {})
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(
      { 'campaign' => origin, 'campaign_touches' => touches }.merge(extra)
    ))
  end

  def stub_ad
    stub_meta_object(id: ad_id, fields: Crm::MetaAds::NameResolver::FIELDS.fetch('ad'),
                     body: { id: ad_id, name: 'Video 2', adset: { id: adset_id, name: 'Conjunto 60+' },
                             campaign: { id: campaign_id, name: 'Viagem EUA' } })
  end

  def touches_after
    conversation.reload.additional_attributes['campaign_touches']
  end

  context 'with an active credential' do
    before { create_meta_ads_connection(account) }

    it 'CTWA: o source_id é o anúncio e o toque ganha os três nomes' do
      set_touches([ctwa_touch])
      stub_ad

      described_class.perform_now(conversation.id)

      touch = touches_after.sole
      expect(touch).to include('ad_name' => 'Video 2', 'adset_name' => 'Conjunto 60+', 'campaign_name' => 'Viagem EUA')
      expect(touch['headline']).to eq('Fale conosco')
      expect(touch.except('ad_name', 'adset_name', 'campaign_name')).to eq(ctwa_touch)
    end

    it 'site: utm_content/utm_term/utm_campaign viram nomes e o headline "Origem · <ID>" vira "Origem · <nome>"' do
      set_touches([site_touch])
      stub_ad
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Viagem EUA',
                                fetched_at: 1.hour.ago)
      Crm::MetaAdObject.create!(account: account, meta_object_id: adset_id, object_type: 'adset', name: 'Conjunto 60+',
                                campaign_id: campaign_id, fetched_at: 1.hour.ago)

      described_class.perform_now(conversation.id)

      touch = touches_after.sole
      expect(touch).to include('ad_name' => 'Video 2', 'adset_name' => 'Conjunto 60+', 'campaign_name' => 'Viagem EUA',
                               'headline' => 'LP Seguro · Viagem EUA')
      expect(touch.except('ad_name', 'adset_name', 'campaign_name', 'headline')).to eq(site_touch.except('headline'))
      origin = conversation.reload.additional_attributes['campaign']
      expect(origin).to include('headline' => 'LP Seguro · Viagem EUA', 'campaign_name' => 'Viagem EUA')
    end

    it 'não mexe no headline de site que já não é "Origem · <ID>"' do
      set_touches([site_touch.merge('headline' => 'LP Seguro · Campanha escrita à mão')])
      stub_ad
      Crm::MetaAdObject.create!(account: account, meta_object_id: campaign_id, object_type: 'campaign', name: 'Viagem EUA',
                                fetched_at: 1.hour.ago)
      Crm::MetaAdObject.create!(account: account, meta_object_id: adset_id, object_type: 'adset', name: 'Conjunto 60+',
                                fetched_at: 1.hour.ago)

      described_class.perform_now(conversation.id)

      expect(touches_after.sole['headline']).to eq('LP Seguro · Campanha escrita à mão')
      expect(touches_after.sole['campaign_name']).to eq('Viagem EUA')
    end

    it 'origem que não é o mesmo toque fica intacta e nenhuma outra chave da conversa some' do
      other_origin = { 'source' => 'meta_organic', 'source_id' => 'link:XYZ234', 'headline' => 'QR da loja' }
      lead_form = { 'link_code' => 'ABC234', 'fields' => [] }
      set_touches([ctwa_touch], origin: other_origin, extra: { 'lead_form' => lead_form, 'outra' => 1 })
      stub_ad

      described_class.perform_now(conversation.id)

      attrs = conversation.reload.additional_attributes
      expect(attrs['campaign']).to eq(other_origin)
      expect(attrs).to include('lead_form' => lead_form, 'outra' => 1)
      expect(attrs['campaign_touches'].sole['ad_name']).to eq('Video 2')
    end

    it 'grava sob lock da linha e preserva um toque que chegou durante a resolução' do
      set_touches([ctwa_touch])
      stub_ad
      late = { 'source' => 'meta_organic', 'source_id' => 'link:LATE23', 'touched_at' => '2026-10-03T12:00:00Z' }
      allow_any_instance_of(Crm::MetaAds::NameResolver).to receive(:resolve).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
        fresh = Conversation.find(conversation.id)
        fresh.update!(additional_attributes: fresh.additional_attributes.merge(
          'campaign_touches' => fresh.additional_attributes['campaign_touches'] + [late]
        ))
        original.call(*args, **kwargs)
      end
      expect_any_instance_of(Conversation).to receive(:with_lock).once.and_call_original # rubocop:disable RSpec/AnyInstance

      described_class.perform_now(conversation.id)

      expect(touches_after.map { |touch| touch['source_id'] }).to eq([ad_id, 'link:LATE23'])
      expect(touches_after.first['ad_name']).to eq('Video 2')
      expect(touches_after.last).to eq(late)
    end

    it 're-transmite os cards quando algum toque mudou' do
      set_touches([ctwa_touch])
      stub_ad

      with_modified_env CRM_KANBAN_ENABLED: 'true' do
        expect { described_class.perform_now(conversation.id) }
          .to have_enqueued_job(Crm::Cards::RebroadcastConversationCardsJob).with(conversation.id)
      end
    end

    it 'toque sem ID não chama a Graph nem regrava a conversa' do
      set_touches([{ 'source' => 'meta_paid', 'source_id' => 'site:ABC234:viagem', 'utm_campaign' => 'Viagem EUA',
                     'utm_content' => '{{ad.id}}', 'touched_at' => '2026-10-02T12:00:00Z' }])
      updated_at = conversation.reload.updated_at

      described_class.perform_now(conversation.id)

      expect(meta_object_requests).not_to have_been_made
      expect(conversation.reload.updated_at).to eq(updated_at)
    end
  end

  it 'sem credencial ativa não faz nada' do
    create_meta_ads_connection(account, status: 'invalid')
    set_touches([ctwa_touch])

    described_class.perform_now(conversation.id)

    expect(meta_object_requests).not_to have_been_made
    expect(touches_after.sole).to eq(ctwa_touch)
  end

  describe '.enqueue_for (gancho do Ctwa::CampaignBuilder)' do
    before do
      Redis::Alfred.delete("#{described_class::KEY_PREFIX}:#{conversation.id}")
      Redis::Alfred.delete("#{described_class::KEY_PREFIX}:#{conversation.id}:trailing")
    end

    after do
      Redis::Alfred.delete("#{described_class::KEY_PREFIX}:#{conversation.id}")
      Redis::Alfred.delete("#{described_class::KEY_PREFIX}:#{conversation.id}:trailing")
    end

    it 'enfileira depois de uma atribuição com ID e segura as seguintes por 5 minutos' do
      create_meta_ads_connection(account)

      expect do
        Ctwa::CampaignBuilder.attribute!(conversation, source_id: ad_id, source_type: 'ad', ctwa_clid: 'clid-a', headline: 'Oi')
      end.to have_enqueued_job(described_class).with(conversation.id).exactly(:once)

      expect do
        Ctwa::CampaignBuilder.attribute!(conversation, source_id: ad_id, source_type: 'ad', ctwa_clid: 'clid-b', headline: 'Oi')
        Ctwa::CampaignBuilder.attribute!(conversation, source_id: ad_id, source_type: 'ad', ctwa_clid: 'clid-c', headline: 'Oi')
      end.to have_enqueued_job(described_class).with(conversation.id).exactly(:once)
      trailing = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find { |job| job[:job] == described_class }
      expect(trailing[:at]).to be_within(5.seconds).of(described_class::THROTTLE.from_now.to_f)
    end

    it 'não enfileira toque sem ID' do
      create_meta_ads_connection(account)

      expect do
        Ctwa::CampaignBuilder.attribute!(conversation, source_id: 'link:ABC234', source_type: 'tracked_link', headline: 'QR')
      end.not_to have_enqueued_job(described_class)
    end

    it 'não enfileira sem credencial ativa' do
      expect do
        Ctwa::CampaignBuilder.attribute!(conversation, source_id: ad_id, source_type: 'ad', ctwa_clid: 'clid-a', headline: 'Oi')
      end.not_to have_enqueued_job(described_class)
    end
  end
end
