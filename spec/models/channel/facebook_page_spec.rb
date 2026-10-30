# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::FacebookPage do
  before do
    stub_request(:post, /graph.facebook.com/)
  end

  let(:channel) { create(:channel_facebook_page) }

  it { is_expected.to validate_presence_of(:account_id) }
  # it { is_expected.to validate_uniqueness_of(:page_id).scoped_to(:account_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for facebook' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:facebook_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end

  it 'has a valid name' do
    expect(channel.name).to eq('Facebook')
  end

  describe '#subscribe' do
    let(:channel) { build(:channel_facebook_page) }
    let(:subscription) { instance_double(Crm::MetaAds::PageSubscription, add!: true, remove!: true) }

    before do
      allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(subscription)
    end

    it 'adds the messenger fields without replacing the other fields of the page' do
      channel.subscribe

      expect(Crm::MetaAds::PageSubscription).to have_received(:new)
        .with(page_id: channel.page_id, access_token: channel.page_access_token)
      expect(subscription).to have_received(:add!).with(include('messages', 'messaging_postbacks'))
    end

    it 'removes only the messenger fields on unsubscribe, keeping leadgen and feed' do
      channel.unsubscribe

      expect(subscription).to have_received(:remove!).with(Channel::FacebookPage::MESSENGER_FIELDS)
    end

    it 'keeps the messenger fields when the page is still an inbox of another account' do
      create(:channel_facebook_page, page_id: channel.page_id)

      channel.unsubscribe

      expect(subscription).not_to have_received(:remove!)
    end
  end

  describe 'connecting a page inbox over the real subscription (#2200)' do
    let(:graph) { "https://graph.facebook.com/#{Meta::ConversionsApiClient::DEFAULT_API_VERSION}" }
    let(:page_id) { '987654321' }
    let(:json) { { 'Content-Type' => 'application/json' } }

    before do
      stub_request(:get, "#{graph}/app").to_return(status: 200, headers: json, body: { id: '544' }.to_json)
    end

    it 'keeps leadgen and feed of the page when the inbox subscribes the messenger fields' do
      wanted = %w[leadgen feed] + Channel::FacebookPage::MESSENGER_FIELDS
      stub_request(:get, "#{graph}/#{page_id}/subscribed_apps").to_return(
        { status: 200, headers: json, body: { data: [{ id: '544', subscribed_fields: %w[leadgen feed] }] }.to_json },
        { status: 200, headers: json, body: { data: [{ id: '544', subscribed_fields: wanted }] }.to_json }
      )
      post = stub_request(:post, "#{graph}/#{page_id}/subscribed_apps")
             .with(body: { subscribed_fields: wanted.join(',') })
             .to_return(status: 200, headers: json, body: { success: true }.to_json)

      create(:channel_facebook_page, page_id: page_id)

      expect(post).to have_been_requested
    end
  end
end
