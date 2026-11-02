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
      allow(client).to receive(:get_session).and_raise(Waha::Client::NotFound.new('404', status: 404))
      allow(client).to receive(:create_session)
      allow(client).to receive(:delete_app)
      allow(client).to receive(:delete_session)
    end

    def provisioner(target_account = account, assigner: WhatsappProxy::Assigner.new)
      described_class.new(account: target_account, phone: '5511999999999', api_access_token: 'account-token',
                          client: client, config: config, proxy_assigner: assigner)
    end

    def channel_attrs(inbox)
      inbox.channel.reload.additional_attributes
    end

    context 'when the account already has an inbox for the number (#2478)' do
      it 'returns the finished inbox when its session is in the engine, without writing to the engine' do
        first = provisioner.perform.inbox
        allow(client).to receive(:get_session).and_return({ 'status' => 'SCAN_QR_CODE' })

        expect { expect(provisioner.perform.inbox).to eq(first) }.not_to change(Inbox, :count)
        expect(client).to have_received(:create_session).once
        expect(channel_attrs(first)).not_to have_key('provisioning_pending')
      end

      it 'finishes the remote side of an inbox left pending by a rollback that could not remove it' do
        allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new('WAHA POST -> 422', status: 422))
        allow_any_instance_of(Inbox).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed) # rubocop:disable RSpec/AnyInstance

        log = capture_log { expect { provisioner.perform }.to raise_error(described_class::Error, 'remote_setup_failed') }
        left = account.inboxes.sole
        expect(log).to include("[Waha] rollback kept inbox=#{left.id}")
        expect(channel_attrs(left)['provisioning_pending']).to be(true)

        allow(client).to receive(:create_session)
        expect(provisioner.perform.inbox).to eq(left)
        expect(channel_attrs(left)).not_to have_key('provisioning_pending')
      end

      it 'refuses a number that is already an inbox in another account' do
        provisioner(create(:account)).perform

        expect { provisioner.perform }.to raise_error(described_class::Error, 'phone_in_use_elsewhere')
        expect(account.inboxes.count).to eq(0)
      end

      it 'ignores a channel without inbox when looking for the owner of the number' do
        create(:channel_api, account: create(:account),
                             additional_attributes: { 'provider' => 'waha', 'session' => '5511999999999' }).inbox.delete

        expect(provisioner.perform.inbox.account).to eq(account)
      end
    end

    context 'when the engine still has the session without any inbox (#2478)' do
      let(:engine_writes) { %i[update_session create_session start_session delete_app delete_session] }

      def chatwoot_app(url: 'https://chatwoot.example/', account_id: account.id)
        { 'id' => 'app_antigo', 'app' => 'chatwoot', 'config' => { 'url' => url, 'accountId' => account_id } }
      end

      before do
        allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
        allow(client).to receive(:list_apps).with('5511999999999').and_return([chatwoot_app])
        allow(client).to receive(:update_session)
        allow(client).to receive(:start_session)
      end

      it 'reuses a stopped session that is ours and of this account: swaps its apps and starts it again' do
        result = provisioner.perform

        expect(client).not_to have_received(:create_session)
        expect(client).to have_received(:update_session).with(
          '5511999999999',
          config: { ignore: hash_including(groups: true) },
          apps: contain_exactly(hash_including(id: result.phone_numbers_app_id), hash_including(id: result.app_id))
        )
        expect(client).to have_received(:start_session).with('5511999999999')
      end

      it 'reuses a connected session that is ours and of this account, without starting it' do
        allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })

        provisioner.perform

        expect(client).to have_received(:update_session)
        expect(client).not_to have_received(:start_session)
      end

      {
        'an app of another account' => [{ 'status' => 'STOPPED' }, -> { [chatwoot_app(account_id: account.id + 1)] }],
        'no apps, waiting for the QR (personal number)' => [{ 'status' => 'SCAN_QR_CODE' }, -> { [] }],
        'no apps, stopped (personal number)' => [{ 'status' => 'STOPPED' }, -> { [] }],
        'an app of another chat URL' => [{ 'status' => 'STOPPED' }, -> { [chatwoot_app(url: 'https://outro.example')] }],
        'an app without accountId' => [{ 'status' => 'WORKING' }, -> { [chatwoot_app.merge('config' => { 'url' => 'https://chatwoot.example' })] }]
      }.each do |kind, (remote, apps)|
        it "refuses a session with #{kind} without writing to the engine or asking for an IP" do
          assigner = instance_double(WhatsappProxy::Assigner, for: nil, release!: 1)
          allow(client).to receive(:get_session).and_return(remote)
          allow(client).to receive(:list_apps).and_return(instance_exec(&apps))

          expect { provisioner(assigner: assigner).perform }.to raise_error(described_class::Error, 'phone_in_use_elsewhere')

          engine_writes.each { |call| expect(client).not_to have_received(call) }
          expect(assigner).not_to have_received(:for)
          expect(assigner).not_to have_received(:release!)
          expect(Inbox.count).to eq(0)
        end
      end

      it 'keeps the proxy the session already had when there is no new IP' do
        proxy = { 'server' => '10.0.0.7:6000', 'username' => 'u', 'password' => 'p' }
        allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED', 'config' => { 'proxy' => proxy } })

        provisioner.perform

        expect(client).to have_received(:update_session)
          .with('5511999999999', config: { ignore: hash_including(groups: true), proxy: proxy }, apps: anything)
      end

      it 'puts the new IP when the assigner has one' do
        assigner = instance_double(WhatsappProxy::Assigner, for: webshare_proxy(id: 9, address: '10.0.0.9'), mark_applied!: 1)
        allow(client).to receive(:get_session)
          .and_return({ 'status' => 'STOPPED', 'config' => { 'proxy' => { 'server' => '10.0.0.7:6000' } } })

        provisioner(assigner: assigner).perform

        expect(client).to have_received(:update_session)
          .with('5511999999999', config: hash_including(proxy: hash_including(server: '10.0.0.9:6000')), apps: anything)
      end

      it 'on failure keeps the session, removes only the apps sent now and restores the IP reservation' do
        allow(Waha::Client).to receive(:new).and_return(client)
        reservation = WhatsappProxy::Assignment.create!(session_name: '5511999999999', account_id: create(:account).id,
                                                        pool: 'datacenter', webshare_proxy_id: '7', proxy_address: '10.0.0.7',
                                                        proxy_port: 6000, assigned_at: 1.day.ago)
        assigner = instance_double(WhatsappProxy::Assigner, release!: 1)
        allow(assigner).to receive(:for) do
          reservation.update!(proxy_address: '10.0.0.9', webshare_proxy_id: '9')
          webshare_proxy(id: 9, address: '10.0.0.9')
        end
        allow(client).to receive(:update_session).and_raise(Waha::Client::Error.new('WAHA PUT -> 500', status: 500))

        expect { provisioner(assigner: assigner).perform }.to raise_error(described_class::Error, 'remote_setup_failed')

        expect(client).to have_received(:delete_app).twice
        expect(client).not_to have_received(:delete_session)
        expect(assigner).not_to have_received(:release!)
        expect(reservation.reload).to have_attributes(account_id: reservation.account_id, proxy_address: '10.0.0.7',
                                                      webshare_proxy_id: '7')
        expect(Inbox.count).to eq(0)
      end

      it 'does not give the old IP back when another account took it meanwhile' do
        allow(Waha::Client).to receive(:new).and_return(client)
        reservation = WhatsappProxy::Assignment.create!(session_name: '5511999999999', account_id: create(:account).id,
                                                        pool: 'datacenter', webshare_proxy_id: '7', proxy_address: '10.0.0.7',
                                                        proxy_port: 6000, assigned_at: 1.day.ago)
        assigner = instance_double(WhatsappProxy::Assigner, release!: 1)
        allow(assigner).to receive(:for) do
          reservation.update!(proxy_address: '10.0.0.9', webshare_proxy_id: '9')
          WhatsappProxy::Assignment.create!(session_name: 'outra', account_id: create(:account).id, pool: 'datacenter',
                                            webshare_proxy_id: '7', proxy_address: '10.0.0.7', proxy_port: 6000,
                                            assigned_at: Time.current)
          webshare_proxy(id: 9, address: '10.0.0.9')
        end
        allow(client).to receive(:update_session).and_raise(Waha::Client::Error.new('WAHA PUT -> 500', status: 500))

        log = capture_log { expect { provisioner(assigner: assigner).perform }.to raise_error(described_class::Error) }

        expect(log).to include('[Waha] proxy undo skipped session=***9999: ActiveRecord::RecordInvalid')
        expect(reservation.reload.proxy_address).to eq('10.0.0.9')
        expect(WhatsappProxy::Assignment.where(proxy_address: '10.0.0.7').count).to eq(1)
      end
    end

    context 'when the account inbox was ready but its session is gone from the engine (#2478)' do
      let!(:inbox) do
        create(:channel_api, account: account, additional_attributes: {
                 'provider' => 'waha', 'session' => '5511999999999', 'app_id' => 'app_old', 'phone_numbers_app_id' => 'br_old'
               }).inbox
      end

      it 'sets the session up again for the same inbox' do
        expect(provisioner.perform.inbox).to eq(inbox)

        expect(client).to have_received(:create_session)
          .with('5511999999999', start: true, config: anything,
                                 apps: contain_exactly(hash_including(id: 'br_old'), hash_including(id: 'app_old')))
      end

      it 'keeps the inbox when setting the session up again fails' do
        allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new('WAHA POST -> 422', status: 422))

        expect { provisioner.perform }.to raise_error(described_class::Error, 'remote_setup_failed')
        expect(Inbox.exists?(inbox.id)).to be(true)
      end

      it 'answers engine_unavailable instead of the inbox when the engine does not answer' do
        allow(client).to receive(:get_session).and_raise(Waha::Client::Timeout, 'WAHA GET sem resposta')

        expect { provisioner.perform }.to raise_error(described_class::Error, 'engine_unavailable')
        expect(client).not_to have_received(:create_session)
      end
    end

    context 'when the engine fails' do
      before { allow(Waha::Client).to receive(:new).and_return(client) }

      it 'deletes the session it may have created, once, when the engine did not answer' do
        allow(client).to receive(:create_session).and_raise(Waha::Client::Timeout, 'WAHA POST /api/sessions sem resposta')

        expect { provisioner.perform }.to raise_error(described_class::Error, 'engine_unavailable')

        expect(client).to have_received(:delete_session).with('5511999999999').once
        expect(Inbox.count).to eq(0)
      end

      it 'deletes nothing remote when the engine refused the session (4xx)' do
        allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new('WAHA POST -> 422', status: 422))

        expect { provisioner.perform }.to raise_error(described_class::Error, 'remote_setup_failed')

        expect(client).not_to have_received(:delete_session)
        expect(client).not_to have_received(:delete_app)
        expect(Inbox.count).to eq(0)
      end

      it 'touches nothing remote when the engine could not even be asked about the session' do
        allow(client).to receive(:get_session).and_raise(Waha::Client::Error.new('WAHA GET falhou: Connection refused'))

        expect { provisioner.perform }.to raise_error(described_class::Error, 'engine_unavailable')

        expect(client).not_to have_received(:delete_app)
        expect(client).not_to have_received(:delete_session)
      end

      [502, 503, 504].each do |status|
        it "answers engine_unavailable when the gateway answers #{status}" do
          allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new("WAHA POST -> #{status}", status: status))

          expect { provisioner.perform }.to raise_error(described_class::Error, 'engine_unavailable')
        end
      end

      it 'logs what the engine said, without the account token or the whole number' do
        allow(client).to receive(:create_session).and_raise(
          Waha::Client::Error.new('WAHA POST /api/sessions/5511999999999 -> 422: session exists account-token', status: 422)
        )

        log = capture_log { expect { provisioner.perform }.to raise_error(described_class::Error) }

        expect(log).to include('Waha::Client::Error', '422: session exists', '***9999')
        expect(log).not_to include('account-token')
        expect(log).not_to include('5511999999999')
      end
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
              linkPreview: 'OFF',
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
      let(:assigner) { instance_double(WhatsappProxy::Assigner, for: proxy, mark_applied!: 1, release!: 1, mark_pending!: nil) }

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
        expect(assigner).to have_received(:mark_pending!).with('5511999999999')
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
        allow(client).to receive(:create_session)
          .and_raise(Waha::Client::Error.new('WAHA POST /api/sessions -> 400: [FILTERED]', status: 400))

        log = capture_log { expect { provision }.to raise_error(described_class::Error, 'remote_setup_failed') }

        expect(assigner).to have_received(:release!).with('5511999999999')
        expect(log).not_to include('senha-9')
      end
    end
  end
end
