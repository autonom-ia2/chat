require 'rails_helper'

# Por onde o anúncio de Messenger e de Direct entra (#2521): a mensagem de conversa nova, o postback e o evento só de
# referral de quem já tinha conversa.
RSpec.describe 'Anúncio de clique para o Messenger e o Direct na entrada' do # rubocop:disable RSpec/DescribeClass
  let(:ad_referral) { { source: 'ADS', type: 'OPEN_THREAD', ad_id: '120200000000000001', ads_context_data: { ad_title: 'Promo' } } }

  describe Messages::Facebook::MessageBuilder do
    let(:channel) { create(:channel_facebook_page) }
    let(:fb_object) { double }

    before do
      stub_request(:post, /graph.facebook.com/)
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return({ first_name: 'Jane', last_name: 'Dae' }.with_indifferent_access)
    end

    def deliver(messaging, outgoing_echo: false)
      parser = Integrations::Facebook::MessageParser.new({ messaging: messaging }.to_json)
      described_class.new(parser, channel.inbox, outgoing_echo: outgoing_echo).perform
    end

    it 'a primeira mensagem com o anúncio grava o toque do Messenger na conversa' do
      deliver({ sender: { id: 'psid-1' }, recipient: { id: channel.page_id },
                message: { mid: 'm_1', text: 'Oi, vi o anúncio', referral: ad_referral } })

      touch = channel.inbox.conversations.sole.additional_attributes['campaign_touches'].sole
      expect(touch).to include('source' => 'meta_ctm', 'source_id' => '120200000000000001', 'referral_id' => 'm_1')
    end

    it 'o postback do "Começar" com o anúncio grava; a mensagem de saída (echo) não' do
      deliver({ sender: { id: 'psid-1' }, recipient: { id: channel.page_id },
                postback: { mid: 'pb_1', title: 'Começar', payload: 'GET_STARTED', referral: ad_referral } })
      deliver({ sender: { id: channel.page_id }, recipient: { id: 'psid-1' },
                message: { mid: 'm_echo', text: 'Olá!', is_echo: true, referral: ad_referral } }, outgoing_echo: true)

      expect(channel.inbox.conversations.sole.additional_attributes['campaign_touches'].pluck('referral_id')).to eq(['pb_1'])
    end

    it 'mensagem sem anúncio não grava toque' do
      deliver({ sender: { id: 'psid-1' }, recipient: { id: channel.page_id }, message: { mid: 'm_2', text: 'Oi' } })

      expect(channel.inbox.conversations.sole.additional_attributes).not_to have_key('campaign_touches')
    end
  end

  describe Messages::Instagram::MessageBuilder do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_instagram, account: account, instagram_id: 'ig-business-1') }
    let(:inbox) { create(:inbox, channel: channel, account: account, greeting_enabled: false) }

    before do
      stub_request(:post, /graph\.instagram\.com/)
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'igsid-1')
    end

    it 'a primeira mensagem com o anúncio grava o toque do Direct na conversa' do
      messaging = { sender: { id: 'igsid-1' }, recipient: { id: 'ig-business-1' }, timestamp: 1_700_000_000,
                    message: { mid: 'ig_m_1', text: 'Quero saber', referral: ad_referral } }.with_indifferent_access

      described_class.new(messaging, inbox).perform

      touch = inbox.conversations.sole.additional_attributes['campaign_touches'].sole
      expect(touch).to include('source' => 'meta_ctd', 'source_id' => '120200000000000001', 'referral_id' => 'ig_m_1')
    end
  end

  describe 'Instagram: postback, echo, mensagem repetida e a conta pela Página do Facebook' do
    let(:account) { create(:account) }

    before { stub_request(:post, /graph\.(instagram|facebook)\.com/) }

    def contact_in(inbox, source_id)
      create(:contact_inbox, contact: create(:contact, account: account), inbox: inbox, source_id: source_id)
    end

    it 'postback grava, echo não, e a mesma mensagem duas vezes grava uma' do
      channel = create(:channel_instagram, account: account, instagram_id: 'ig-business-1')
      contact_in(channel.inbox, 'igsid-1')
      first = { sender: { id: 'igsid-1' }, recipient: { id: 'ig-business-1' }, message: { mid: 'ig_pb_1', text: 'Começar' },
                postback: { mid: 'ig_pb_1', title: 'Começar', referral: ad_referral } }.with_indifferent_access
      echo = { sender: { id: 'ig-business-1' }, recipient: { id: 'igsid-1' },
               message: { mid: 'ig_echo', text: 'Olá', is_echo: true, referral: ad_referral } }.with_indifferent_access

      2.times { Messages::Instagram::MessageBuilder.new(first, channel.inbox).perform }
      Messages::Instagram::MessageBuilder.new(echo, channel.inbox, outgoing_echo: true).perform

      expect(channel.inbox.conversations.sole.additional_attributes['campaign_touches'].pluck('referral_id')).to eq(['ig_pb_1'])
    end

    it 'a conta do Instagram ligada pela Página do Facebook grava o toque do Direct' do
      channel = create(:channel_instagram_fb_page, account: account, instagram_id: 'ig-page-business-1')
      inbox = create(:inbox, channel: channel, account: account)
      contact_in(inbox, 'igsid-2')
      messaging = { sender: { id: 'igsid-2' }, recipient: { id: 'ig-page-business-1' },
                    message: { mid: 'ig_m_2', text: 'Oi', referral: ad_referral } }.with_indifferent_access

      Messages::Instagram::Messenger::MessageBuilder.new(messaging, inbox).perform

      expect(inbox.conversations.sole.additional_attributes['campaign_touches'].sole).to include('source' => 'meta_ctd', 'referral_id' => 'ig_m_2')
    end
  end

  describe Webhooks::InstagramEventsJob do
    it 'o evento só de referral vai para o job do anúncio com o remetente e a hora' do
      create(:channel_instagram, instagram_id: 'ig-business-1')
      entry = { id: 'ig-business-1', time: 1_700_000_000,
                messaging: [{ sender: { id: 'igsid-1' }, recipient: { id: 'ig-business-1' }, timestamp: 1_700_000_000,
                              referral: ad_referral }] }.with_indifferent_access

      expect { described_class.perform_now([entry]) }.to have_enqueued_job(Crm::MetaAds::MessagingReferralJob)
        .with('instagram', 'ig-business-1', 'igsid-1', hash_including('ad_id' => '120200000000000001'), '1700000000')
    end
  end

  describe 'Facebook::Messenger::Bot.on :referral' do
    it 'o evento só de referral do Messenger vai para o job do anúncio' do
      messaging = { 'sender' => { 'id' => 'psid-1' }, 'recipient' => { 'id' => 'page-1' }, 'timestamp' => 1_700_000_000,
                    'referral' => ad_referral.deep_stringify_keys }

      expect { Facebook::Messenger::Bot.receive(messaging) }.to have_enqueued_job(Crm::MetaAds::MessagingReferralJob)
        .with('messenger', 'page-1', 'psid-1', hash_including('ad_id' => '120200000000000001'), '1700000000')
    end
  end
end
