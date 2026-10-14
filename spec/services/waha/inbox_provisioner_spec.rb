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

    context 'with a Webshare proxy (#1516)' do
      let(:proxy) { webshare_proxy(id: 9, address: '10.0.0.9') }
      let(:assigner) { instance_double(WhatsappProxy::Assigner, for: proxy, mark_applied!: 1, release!: 1) }

      def provision
        described_class.new(account: account, phone: '5511999999999', api_access_token: 'account-token',
                            client: client, config: config, proxy_assigner: assigner).perform
      end

      it 'creates the session with its own proxy and records it as applied' do
        provision

        expect(client).to have_received(:create_session).with(
          '5511999999999', start: true, apps: anything,
                           config: { ignore: hash_including(groups: true),
                                     proxy: { server: '10.0.0.9:6000', username: 'user-9', password: 'senha-9' } }
        )
        expect(assigner).to have_received(:mark_applied!).with('5511999999999', proxy)
      end

      it 'creates the session without proxy when none is available' do
        allow(assigner).to receive(:for).and_return(nil)

        provision

        expect(client).to have_received(:create_session)
          .with('5511999999999', start: true, apps: anything, config: { ignore: hash_including(groups: true) })
      end

      it 'gives the new inbox a datacenter IP through the real Assigner (fake Webshare and engine)' do
        engine = instance_double(Waha::Client, list_sessions: [])
        datacenter = fake_pool('datacenter', [webshare_proxy(id: 3, address: '10.0.0.3'), webshare_proxy(id: 4, address: '10.0.0.4')])
        real = WhatsappProxy::Assigner.new(engine: engine, pools: { isp: fake_pool('isp', []), datacenter: datacenter })
        WhatsappProxy::Assignment.create!(session_name: 'outra', account_id: create(:account).id, pool: 'datacenter',
                                          webshare_proxy_id: '3', proxy_address: '10.0.0.3', proxy_port: 6000,
                                          assigned_at: Time.current)

        with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_API_KEY: 'k',
                          WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.3,10.0.0.4') do
          described_class.new(account: account, phone: '5511999999999', api_access_token: 'account-token',
                              client: client, config: config, proxy_assigner: real).perform
        end

        expect(client).to have_received(:create_session)
          .with('5511999999999', start: true, apps: anything, config: hash_including(proxy: hash_including(server: '10.0.0.4:6000')))
        record = WhatsappProxy::Assignment.find_by!(session_name: '5511999999999')
        expect(record).to have_attributes(account_id: account.id, pool: 'datacenter', origin: 'assigned')
        expect(record.credential_digest).to be_present
      end

      it 'frees the IP and keeps the credential out of the log when the engine refuses the session' do
        allow(Waha::Client).to receive(:new).and_return(client)
        allow(client).to receive(:create_session).and_raise(Waha::Client::Error, 'WAHA POST /api/sessions -> 400: [FILTERED]')

        log = capture_log { expect { provision }.to raise_error(described_class::Error, 'remote_setup_failed') }

        expect(assigner).to have_received(:release!).with('5511999999999')
        expect(log).not_to include('senha-9')
      end
    end
  end
end
