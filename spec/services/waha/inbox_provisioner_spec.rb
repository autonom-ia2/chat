require 'rails_helper'

RSpec.describe Waha::InboxProvisioner do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:client) { instance_double(Waha::Client) }
    let(:config) do
      class_double(
        Waha::Config,
        enabled?: true,
        callback_url: 'https://waha.example/webhooks/chatwoot/5511999999999/app_id',
        session_ignore: { status: true, broadcast: true, channels: true, groups: true },
        chatwoot_base_url: 'https://chatwoot.example'
      )
    end

    before do
      allow(client).to receive(:create_session)
      allow(client).to receive(:delete_app)
      allow(client).to receive(:delete_session)
    end

    it 'creates the WAHA inbox locked to a single conversation' do
      result = described_class.new(
        account: account,
        phone: '5511999999999',
        api_access_token: 'account-token',
        client: client,
        config: config
      ).perform

      expect(result.inbox.lock_to_single_conversation).to be(true)
    end

    it 'creates the session with Brazilian number resolution and Chatwoot configured before start' do
      result = described_class.new(
        account: account,
        phone: '5511999999999',
        api_access_token: 'account-token',
        client: client,
        config: config
      ).perform

      expect(result.inbox.channel.additional_attributes['phone_numbers_app_id']).to eq(result.phone_numbers_app_id)
      expect(client).to have_received(:create_session).with(
        '5511999999999',
        start: true,
        config: { ignore: hash_including(groups: true) },
        apps: contain_exactly(
          hash_including(
            id: result.phone_numbers_app_id,
            app: 'brazilian-phone-numbers',
            enabled: true,
            config: hash_including(
              strict: false,
              lookup: true,
              cache: hash_including(persistent: true)
            )
          ),
          hash_including(
            id: result.app_id,
            app: 'chatwoot',
            enabled: true,
            config: hash_including(
              groups: 'OFF',
              conversations: hash_including(
                outgoing: 'message',
                syncMessageStatus: true,
                sort: 'created_newest',
                status: nil
              )
            )
          )
        )
      )
    end
  end
end
