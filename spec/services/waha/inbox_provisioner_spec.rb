require 'rails_helper'

RSpec.describe Waha::InboxProvisioner do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:token_owner) { create(:user, account: account, role: :administrator) }
    let(:api_access_token) { token_owner.access_token.token }
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
      allow(client).to receive(:history_source_ids_available?).and_return(true)
      allow(client).to receive(:get_session).and_raise(Waha::Client::Error.new('not_found', status: 404))
      allow(client).to receive(:create_session)
      allow(client).to receive(:delete_app)
      allow(client).to receive(:delete_session)
    end

    it 'creates the WAHA inbox locked to a single conversation' do
      result = described_class.new(
        account: account,
        phone: '5511999999999',
        api_access_token: api_access_token,
        client: client,
        config: config
      ).perform

      expect(result.inbox.lock_to_single_conversation).to be(true)
      expect(result.inbox.channel.additional_attributes['account_token_owner_user_id']).to eq(token_owner.id)
    end

    it 'marks only the new connection and schedules its history after remote provisioning succeeds' do
      result = described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                                   client: client, config: config).perform

      marker = result.inbox.channel.additional_attributes.fetch('waha_history_import')
      expect(marker).to include('status' => 'waiting_connection', 'pass' => 0, 'chat_id' => nil)
      expect(marker['before']).to eq(0)
      expect(Waha::HistoryImportJob).to have_been_enqueued.with(result.inbox.id)
    end

    it 'refuses a new connection before any write when the connector cannot deduplicate history' do
      allow(client).to receive(:history_source_ids_available?).and_return(false)
      expect(client).not_to receive(:create_session)

      expect do
        described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                            client: client, config: config).perform
      end.to raise_error(described_class::Error, 'history_connector_unavailable')
      expect(account.inboxes.count).to eq(0)
    end

    it 'does not schedule an import when remote provisioning fails' do
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_session).and_raise(Waha::Client::Error, 'provider_unavailable')

      expect do
        described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                            client: client, config: config).perform
      end.to raise_error(described_class::Error, 'remote_setup_failed')
      expect(Waha::HistoryImportJob).not_to have_been_enqueued
    end

    it 'preserves an existing session and rejects creation before local writes' do
      allow(client).to receive(:get_session).and_return('status' => 'WORKING')
      expect(client).not_to receive(:create_session)
      expect(client).not_to receive(:delete_app)
      expect(client).not_to receive(:delete_session)

      expect do
        described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                            client: client, config: config).perform
      end.to raise_error(described_class::Error, 'session_already_exists')
      expect(account.inboxes.count).to eq(0)
    end

    [409, nil].each do |status|
      it "never deletes remote data after a conflicting or ambiguous POST (#{status.inspect})" do
        allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new('remote_error', status: status))
        allow(Waha::Client).to receive(:new).and_return(client)
        expect(client).not_to receive(:delete_app)
        expect(client).not_to receive(:delete_session)

        expect do
          described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                              client: client, config: config).perform
        end.to raise_error(described_class::Error, 'remote_setup_failed')
        expect(account.inboxes.count).to eq(0)
        expect(account.api_channels.count).to eq(0)
        expect(Waha::HistoryImportJob).not_to have_been_enqueued
      end
    end

    it 'fails closed when the existence check is unavailable' do
      allow(client).to receive(:get_session).and_raise(Waha::Client::Error.new('unavailable', status: 503))
      expect(client).not_to receive(:create_session)
      expect(client).not_to receive(:delete_session)

      expect do
        described_class.new(account: account, phone: '5511999999999', api_access_token: api_access_token,
                            client: client, config: config).perform
      end.to raise_error(described_class::Error, 'session_check_failed')
      expect(account.inboxes.count).to eq(0)
    end

    it 'creates the session with Brazilian number resolution and Chatwoot configured before start' do
      result = described_class.new(
        account: account,
        phone: '5511999999999',
        api_access_token: api_access_token,
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
