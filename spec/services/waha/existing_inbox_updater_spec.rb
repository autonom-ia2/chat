require 'rails_helper'

RSpec.describe Waha::ExistingInboxUpdater do
  let(:account) { create(:account) }
  let(:client) { instance_double(Waha::Client) }
  let(:output) { StringIO.new }
  let(:service) do
    described_class.new(
      client: client,
      output: output,
      sleeper: ->(_) {},
      health_attempts: 3,
      health_interval: 0
    )
  end
  let(:channel) do
    create(
      :channel_api,
      account: account,
      additional_attributes: {
        'provider' => 'waha',
        'session' => '5511999999999',
        'app_id' => 'app_123'
      }
    )
  end
  let!(:inbox) do
    channel.inbox.tap { |record| record.update!(lock_to_single_conversation: false) }
  end
  let(:remote_app) do
    {
      'id' => 'app_123',
      'session' => '5511999999999',
      'app' => 'chatwoot',
      'enabled' => true,
      'config' => {
        'url' => 'https://chat.example',
        'accountId' => account.id,
        'inboxId' => inbox.id,
        'inboxIdentifier' => channel.identifier,
        'groups' => 'OFF',
        'conversations' => {
          'markAsRead' => true,
          'sort' => 'created_newest',
          'status' => nil
        },
        'customFutureOption' => { 'keep' => true }
      }
    }
  end
  let(:remote_phone_app) { nil }
  let(:remote_other_app) { nil }
  let(:remote_session) do
    {
      'name' => '5511999999999',
      'status' => 'WORKING',
      'config' => { 'ignore' => { 'status' => true, 'groups' => true } }
    }
  end
  let(:remote_apps) do
    [remote_app.deep_dup, remote_phone_app&.deep_dup, remote_other_app&.deep_dup].compact
  end

  before do
    allow(Waha::Config).to receive(:chatwoot_base_url).and_return('https://chat.example')
    allow(client).to receive(:get_app).with('app_123') do
      remote_apps.find { |app| app['id'] == 'app_123' }&.deep_dup
    end
    allow(client).to receive(:get_session).with('5511999999999') { remote_session.deep_dup }
    allow(client).to receive(:list_apps).with('5511999999999') { remote_apps.deep_dup }
    allow(client).to receive(:brazilian_phone_numbers_available?).with('5511999999999').and_return(true)
    allow(client).to receive(:start_session).with('5511999999999') do
      remote_session['status'] = 'WORKING'
      remote_session.deep_dup
    end
    allow(client).to receive(:update_session) do |_session, config:, apps:|
      remote_session['config'] = config.deep_dup
      remote_session['status'] = 'WORKING'
      remote_apps.replace(apps.deep_dup)
      remote_session.merge('apps' => remote_apps.deep_dup)
    end
  end

  it 'is dry-run by default and reports all required changes without writing' do
    result = service.perform

    expect(result.to_h.slice(:would_update, :updated, :failed)).to eq(would_update: 1, updated: 0, failed: 0)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
    expect(client).not_to have_received(:update_session)
    expect(output.string).to include('brazilian_phone_numbers_app')
    expect(output.string).to include('DRY_RUN')
  end

  it 'updates remote state, confirms WORKING and only then records local state' do
    result = service.perform(apply: true)

    expect(result.updated).to eq(1)
    expect(result.failed).to eq(0)
    expect(result.halted).to be(false)
    expect(remote_session['status']).to eq('WORKING')
    expect(inbox.reload.lock_to_single_conversation).to be(true)

    phone_app_id = channel.reload.additional_attributes['phone_numbers_app_id']
    expect(phone_app_id).to start_with('br_')
    expect(remote_apps).to contain_exactly(
      hash_including(
        'id' => phone_app_id,
        'app' => 'brazilian-phone-numbers',
        'enabled' => true
      ),
      hash_including(
        'id' => 'app_123',
        'app' => 'chatwoot',
        'config' => hash_including(
          'conversations' => hash_including(
            'outgoing' => 'message',
            'syncMessageStatus' => true
          )
        )
      )
    )
  end

  describe 'inbox scope' do
    let!(:other_channel) do
      create(:channel_api, account: account,
                           additional_attributes: { 'provider' => 'waha', 'session' => 'other', 'app_id' => 'app_other' })
    end
    let!(:other_account_channel) do
      create(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => 'outside', 'app_id' => 'app_outside' })
    end

    before do
      other_channel.inbox.update!(lock_to_single_conversation: false)
      other_account_channel.inbox.update!(lock_to_single_conversation: false)
    end

    [false, true].each do |apply|
      [false, true].each do |filter_account|
        it "processes only the selected inbox with apply=#{apply} and account filter=#{filter_account}", :aggregate_failures do
          result = service.perform(apply: apply, inbox_id: inbox.id, account_id: filter_account ? account.id : nil)

          expect(result.to_h.slice(:total, :would_update, :updated, :failed, :skipped, :halted)).to eq(
            total: 1, would_update: 1, updated: apply ? 1 : 0, failed: 0, skipped: 0, halted: false
          )
          expect(client).to have_received(:get_app).with('app_123').once
          expect(client).not_to have_received(:get_app).with('app_other')
          expect(client).not_to have_received(:get_app).with('app_outside')
          expect(inbox.reload.lock_to_single_conversation).to be(apply)
          expect(other_channel.inbox.reload.lock_to_single_conversation).to be(false)
          expect(other_account_channel.inbox.reload.lock_to_single_conversation).to be(false)
          expect(other_channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
          expect(other_account_channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
          if apply
            expect(client).to have_received(:update_session).with('5511999999999', config: anything, apps: anything).once
          else
            expect(client).not_to have_received(:update_session)
            expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
          end
        end
      end
    end

    it 'does not fall back to another inbox when account and inbox do not match' do
      result = service.perform(apply: true, account_id: other_account_channel.account_id, inbox_id: inbox.id)

      expect(result.total).to eq(0)
      expect(client).not_to have_received(:get_app)
      expect(client).not_to have_received(:update_session)
      expect(inbox.reload.lock_to_single_conversation).to be(false)
    end

    it 'does not process any inbox when the selected inbox does not exist' do
      missing_id = Inbox.maximum(:id) + 1

      result = service.perform(apply: true, inbox_id: missing_id)

      expect(result.total).to eq(0)
      expect(client).not_to have_received(:get_app)
      expect(client).not_to have_received(:update_session)
    end

    it 'does not process the selected inbox when its channel is not WAHA' do
      channel.update!(additional_attributes: channel.additional_attributes.merge('provider' => 'other'))

      result = service.perform(apply: true, inbox_id: inbox.id)

      expect(result.total).to eq(0)
      expect(client).not_to have_received(:get_app)
      expect(client).not_to have_received(:update_session)
      expect(inbox.reload.lock_to_single_conversation).to be(false)
    end
  end

  describe 'inconsistent Chatwoot reads during planning' do
    {
      'known configuration' => ->(app) { app['config']['conversations']['markAsRead'] = false },
      'unknown configuration' => ->(app) { app['config']['customFutureOption']['keep'] = false },
      'enabled state' => ->(app) { app['enabled'] = false },
      'unknown App fields' => ->(app) { app['customRemoteField'] = 'concurrent' }
    }.each do |field, concurrent_change|
      it "preserves concurrent #{field} and stops the batch without writing", :aggregate_failures do
        second_channel = create(
          :channel_api,
          account: account,
          additional_attributes: { 'provider' => 'waha', 'session' => 'second', 'app_id' => 'app_second' }
        )
        second_channel.inbox.update!(lock_to_single_conversation: false)
        allow(client).to receive(:get_app).with('app_second').and_return({})
        original_attributes = channel.additional_attributes.deep_dup
        expected_apps = nil
        allow(client).to receive(:get_app).with('app_123') do
          initial_app = remote_apps.first.deep_dup
          concurrent_change.call(remote_apps.first)
          expected_apps = remote_apps.deep_dup
          initial_app
        end

        result = service.perform(apply: true)

        expect(result.to_h).to eq(
          total: 1, would_update: 0, updated: 0, unchanged: 0, skipped: 1, failed: 0,
          recovered: 0, recovery_failed: 0, halted: true
        )
        expect(client).to have_received(:list_apps).with('5511999999999').once
        expect(client).not_to have_received(:update_session)
        expect(client).not_to have_received(:start_session)
        expect(client).not_to have_received(:get_app).with('app_second')
        expect(remote_apps).to eq(expected_apps)
        expect(channel.reload.additional_attributes).to eq(original_attributes)
        expect(inbox.reload.lock_to_single_conversation).to be(false)
        expect(second_channel.inbox.reload.lock_to_single_conversation).to be(false)
        expect(output.string).to include('SKIP', 'Chatwoot mudou entre as leituras', 'Nenhuma alteração foi aplicada')
        expect(output.string).not_to include('UPDATED', 'RECOVERED')
      end
    end

    it 'reports the inconsistent snapshot in dry-run without a migration plan or local write', :aggregate_failures do
      allow(client).to receive(:get_app).with('app_123') do
        initial_app = remote_apps.first.deep_dup
        remote_apps.first['config']['customFutureOption']['keep'] = false
        initial_app
      end

      result = service.perform

      expect(result.to_h.slice(:total, :would_update, :updated, :skipped, :halted)).to eq(
        total: 1, would_update: 0, updated: 0, skipped: 1, halted: false
      )
      expect(client).not_to have_received(:update_session)
      expect(client).not_to have_received(:start_session)
      expect(remote_apps.first.dig('config', 'customFutureOption', 'keep')).to be(false)
      expect(inbox.reload.lock_to_single_conversation).to be(false)
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
      expect(output.string).to include('SKIP', 'Chatwoot mudou entre as leituras')
    end

    it 'still blocks a Chatwoot App missing from the complete list', :aggregate_failures do
      allow(client).to receive(:list_apps).with('5511999999999').and_return([])

      result = service.perform(apply: true)

      expect(result.to_h.slice(:updated, :skipped, :halted)).to eq(updated: 0, skipped: 1, halted: true)
      expect(client).not_to have_received(:update_session)
      expect(inbox.reload.lock_to_single_conversation).to be(false)
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
      expect(output.string).to include('chatwoot app absent from session app list')
    end
  end

  describe 'remote changes after planning' do
    let(:concurrent_calls_app) do
      {
        'id' => 'calls_concurrent',
        'session' => '5511999999999',
        'app' => 'calls',
        'enabled' => true,
        'config' => { 'reject' => false }
      }
    end

    shared_examples 'a concurrent change that stops the batch without writing' do
      it 'preserves the concurrent state, skips local writes and does not process the next inbox', :aggregate_failures do
        second_channel = create(
          :channel_api,
          account: account,
          additional_attributes: { 'provider' => 'waha', 'session' => 'second', 'app_id' => 'app_second' }
        )
        second_channel.inbox.update!(lock_to_single_conversation: false)
        allow(client).to receive(:get_app).with('app_second').and_return({})
        original_local_attributes = channel.additional_attributes.deep_dup
        expected_apps = nil
        expected_session = nil
        planner = Waha::ExistingInboxMigrationPlanner.new(client: client)
        allow(Waha::ExistingInboxMigrationPlanner).to receive(:new).with(client: client).and_return(planner)
        allow(planner).to receive(:build).and_wrap_original do |method, *args|
          plan = method.call(*args)
          concurrent_change.call
          expected_apps = remote_apps.deep_dup
          expected_session = remote_session.deep_dup
          plan
        end

        result = service.perform(apply: true)

        expect(result.to_h.slice(:total, :updated, :skipped, :failed, :recovered, :recovery_failed, :halted)).to eq(
          total: 1, updated: 0, skipped: 1, failed: 0, recovered: 0, recovery_failed: 0, halted: true
        )
        expect(client).not_to have_received(:update_session)
        expect(client).not_to have_received(:start_session)
        expect(client).not_to have_received(:get_app).with('app_second')
        expect(remote_apps).to eq(expected_apps)
        expect(remote_session).to eq(expected_session)
        expect(inbox.reload.lock_to_single_conversation).to be(false)
        expect(channel.reload.additional_attributes).to eq(original_local_attributes)
        expect(second_channel.inbox.reload.lock_to_single_conversation).to be(false)
        expect(output.string).to include('SKIP', 'mudou após o planejamento', 'Nenhuma alteração foi aplicada')
        expect(output.string).not_to include('UPDATED')
      end
    end

    context 'when a calls app is added after the initial Chatwoot-only snapshot' do
      let(:concurrent_change) { -> { remote_apps << concurrent_calls_app.deep_dup } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when Chatwoot configuration changes' do
      let(:concurrent_change) { -> { remote_apps.first['config']['customFutureOption']['keep'] = false } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when Brazilian Phone Numbers configuration changes' do
      let(:remote_phone_app) do
        Waha::BrazilianPhoneNumbers.app_payload(session: '5511999999999', app_id: 'br_existing').deep_stringify_keys
      end
      let(:concurrent_change) { -> { remote_apps.last['config']['lookup'] = false } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when an unrelated app changes' do
      let(:remote_other_app) { concurrent_calls_app }
      let(:concurrent_change) { -> { remote_apps.last['enabled'] = false } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when an app is removed' do
      let(:remote_other_app) { concurrent_calls_app }
      let(:concurrent_change) { -> { remote_apps.pop } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when session configuration changes' do
      let(:concurrent_change) { -> { remote_session['config']['ignore']['groups'] = false } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    context 'when the session stops working' do
      let(:concurrent_change) { -> { remote_session['status'] = 'STOPPED' } }

      it_behaves_like 'a concurrent change that stops the batch without writing'
    end

    it 'fails closed and stops without recovery when the final remote read fails' do
      reads = 0
      allow(client).to receive(:list_apps) do
        reads += 1
        raise Waha::Client::Error, 'read failed' if reads > 1

        remote_apps.deep_dup
      end

      result = service.perform(apply: true)

      expect(result.to_h.slice(:updated, :failed, :recovered, :halted)).to eq(updated: 0, failed: 1, recovered: 0, halted: true)
      expect(client).not_to have_received(:update_session)
      expect(inbox.reload.lock_to_single_conversation).to be(false)
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
    end
  end

  describe 'single-conversation compatibility' do
    it 'migrates restrictive remote filters to created_newest and any status before locking the inbox' do
      remote_app['config']['conversations'].merge!(
        'sort' => 'activity_newest',
        'status' => %w[open pending snoozed],
        'customConversationOption' => 'keep-me'
      )
      remote_apps.replace([remote_app.deep_dup])

      result = service.perform(apply: true)

      migrated = remote_apps.find { |app| app['id'] == 'app_123' }
      expect(result.to_h.slice(:updated, :failed, :halted)).to eq(updated: 1, failed: 0, halted: false)
      expect(migrated.dig('config', 'conversations')).to include(
        'sort' => 'created_newest',
        'status' => nil,
        'customConversationOption' => 'keep-me'
      )
      expect(inbox.reload.lock_to_single_conversation).to be(true)
    end

    it 'reports the remote Chatwoot app as needing migration in dry-run when filters are restrictive' do
      inbox.update!(lock_to_single_conversation: true)
      remote_app['config']['conversations'].merge!(
        'outgoing' => 'message',
        'syncMessageStatus' => true,
        'sort' => 'activity_newest',
        'status' => %w[open pending snoozed]
      )
      remote_apps.replace([remote_app.deep_dup])

      result = service.perform

      expect(result.would_update).to eq(1)
      expect(output.string).to include('remote_chatwoot_app')
      expect(client).not_to have_received(:update_session)
    end
  end

  describe 'remote target identity validation' do
    {
      'url' => ['url', 'https://other-installation.example'],
      'accountId' => ['accountId', 999_999],
      'inboxId' => ['inboxId', 888_888],
      'inboxIdentifier' => %w[inboxIdentifier wrong-inbox-identifier]
    }.each do |label, (field, wrong_value)|
      it "blocks apply when remote #{label} does not match the local target" do
        remote_app['config'][field] = wrong_value

        result = service.perform(apply: true)

        expect(result.to_h.slice(:skipped, :updated, :halted)).to eq(skipped: 1, updated: 0, halted: true)
        expect(client).not_to have_received(:update_session)
        expect([inbox.reload.lock_to_single_conversation, channel.reload.additional_attributes['phone_numbers_app_id']])
          .to eq([false, nil])
        expect(output.string).to include("remote_target_mismatch:#{label}")
      end
    end

    it 'accepts only a trailing-slash difference in the installation URL' do
      remote_app['config']['url'] = 'https://chat.example/'

      result = service.perform

      expect(result.would_update).to eq(1)
      expect(result.skipped).to eq(0)
    end

    it 'blocks before remote reads that could migrate when local account ownership is inconsistent' do
      other_account = create(:account)
      inbox.update_column(:account_id, other_account.id) # rubocop:disable Rails/SkipsModelValidations

      result = service.perform(apply: true)

      expect(result.to_h.slice(:skipped, :updated, :halted)).to eq(skipped: 1, updated: 0, halted: true)
      expect(client).not_to have_received(:update_session)
      expect(output.string).to include('local_account_mismatch')
    ensure
      inbox.update_column(:account_id, account.id) if inbox.persisted? # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'blocks apply before any write when the Brazilian resolver module is unavailable' do
    allow(client).to receive(:brazilian_phone_numbers_available?).and_return(false)

    result = service.perform(apply: true)

    expect(result.skipped).to eq(1)
    expect(result.updated).to eq(0)
    expect(result.halted).to be(true)
    expect(client).not_to have_received(:update_session)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(output.string).to include('brazilian_phone_numbers_unavailable')
  end

  it 'blocks apply before any write when the session is not WORKING' do
    remote_session['status'] = 'FAILED'

    result = service.perform(apply: true)

    expect(result.skipped).to eq(1)
    expect(result.halted).to be(true)
    expect(client).not_to have_received(:update_session)
    expect(output.string).to include('session_not_working:FAILED')
  end

  context 'when another WAHA app already exists on the session' do
    let(:remote_other_app) do
      {
        'id' => 'calls_existing',
        'session' => '5511999999999',
        'app' => 'calls',
        'enabled' => true,
        'config' => { 'reject' => false }
      }
    end

    it 'migrates normally when only the order of the remote app list changes' do
      reads = 0
      allow(client).to receive(:list_apps) do
        reads += 1
        reads == 1 ? remote_apps.deep_dup : remote_apps.reverse.deep_dup
      end

      result = service.perform(apply: true)

      expect(result.to_h.slice(:updated, :skipped, :failed, :halted)).to eq(updated: 1, skipped: 0, failed: 0, halted: false)
      expect(client).to have_received(:update_session).once
      expect(remote_apps).to include(remote_other_app)
      expect(inbox.reload.lock_to_single_conversation).to be(true)
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_present
    end

    it 'preserves the unrelated app while syncing the managed apps' do
      service.perform(apply: true)

      expect(remote_apps).to include(remote_other_app)
    end
  end

  context 'when the Brazilian resolver already exists' do
    let(:remote_phone_app) do
      {
        'id' => 'br_existing',
        'session' => '5511999999999',
        'app' => 'brazilian-phone-numbers',
        'enabled' => true,
        'config' => {
          'strict' => false,
          'lookup' => true,
          'cache' => {
            'memoryTtl' => '24h',
            'persistent' => true,
            'persistentTtl' => '31d'
          }
        }
      }
    end

    it 'is idempotent when remote and local state are already compliant' do
      inbox.update!(lock_to_single_conversation: true)
      channel.update!(
        additional_attributes: channel.additional_attributes.merge('phone_numbers_app_id' => 'br_existing')
      )
      remote_app['config']['conversations'].merge!(
        'outgoing' => 'message',
        'syncMessageStatus' => true
      )
      remote_apps.replace([remote_app.deep_dup, remote_phone_app.deep_dup])

      result = service.perform(apply: true)

      expect(result.unchanged).to eq(1)
      expect(result.updated).to eq(0)
      expect(client).not_to have_received(:update_session)
      expect(output.string).to include('already compliant')
    end

    it 'repairs resolver settings while preserving unknown config' do
      remote_phone_app['enabled'] = false
      remote_phone_app['config']['lookup'] = false
      remote_phone_app['config']['customFutureOption'] = { 'keep' => true }
      remote_apps.replace([remote_app.deep_dup, remote_phone_app.deep_dup])

      service.perform(apply: true)

      resolved = remote_apps.find { |app| app['id'] == 'br_existing' }
      expect(resolved).to include('enabled' => true)
      expect(resolved['config']).to include(
        'lookup' => true,
        'strict' => false,
        'customFutureOption' => { 'keep' => true }
      )
      expect(resolved.dig('config', 'cache', 'persistent')).to be(true)
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to eq('br_existing')
    end
  end

  describe 'health at final confirmation' do
    let(:remote_other_app) do
      { 'id' => 'calls_existing', 'session' => '5511999999999', 'app' => 'calls', 'enabled' => true, 'config' => {} }
    end
    let!(:second_channel) do
      create(:channel_api, account: account,
                           additional_attributes: { 'provider' => 'waha', 'session' => 'second', 'app_id' => 'app_second' })
    end

    [true, false].each do |recovery_healthy|
      it "halts without local writes when final health is STOPPED and recovery health is #{recovery_healthy}", :aggregate_failures do
        original_config = remote_session['config'].deep_dup
        original_apps = remote_apps.deep_dup
        original_attributes = channel.additional_attributes.deep_dup
        second_attributes = second_channel.additional_attributes.deep_dup
        second_channel.inbox.update!(lock_to_single_conversation: false)
        update_calls = 0
        reads_after_update = 0
        allow(client).to receive(:get_app).with('app_second').and_return(nil)

        allow(client).to receive(:update_session) do |_session, config:, apps:|
          update_calls += 1
          reads_after_update = 0
          remote_session['config'] = config.deep_dup
          remote_session['status'] = 'WORKING'
          remote_apps.replace(apps.deep_dup)
          remote_session.deep_dup
        end
        allow(client).to receive(:get_session).with('5511999999999') do
          reads_after_update += 1 if update_calls.positive?
          desired_confirmation = update_calls == 1 && reads_after_update == 2
          recovery_confirmation = update_calls == 2 && reads_after_update == 3
          remote_session['status'] = 'STOPPED' if desired_confirmation || (recovery_confirmation && !recovery_healthy)
          remote_session.deep_dup
        end

        result = service.perform(apply: true)

        expect(result.to_h.slice(:total, :updated, :failed, :recovered, :recovery_failed, :halted)).to eq(
          total: 1, updated: 0, failed: 1, recovered: recovery_healthy ? 1 : 0,
          recovery_failed: recovery_healthy ? 0 : 1, halted: true
        )
        expect(update_calls).to eq(2)
        expect(remote_session['config']).to eq(original_config)
        expect(remote_session['status']).to eq(recovery_healthy ? 'WORKING' : 'STOPPED')
        expect(remote_apps).to eq(original_apps)
        expect(channel.reload.additional_attributes).to eq(original_attributes)
        expect(second_channel.reload.additional_attributes).to eq(second_attributes)
        expect([inbox.reload.lock_to_single_conversation, second_channel.inbox.reload.lock_to_single_conversation]).to eq([false, false])
        expect(client).not_to have_received(:get_app).with('app_second')
        expect(output.string).to include(recovery_healthy ? 'RECOVERED' : 'CRITICAL')
        expect(output.string).not_to include('UPDATED')
      end
    end
  end

  it 'restores the original remote snapshot, returns to WORKING and halts after a partial remote failure' do
    original_config = remote_session['config'].deep_dup
    original_apps = remote_apps.deep_dup
    update_calls = 0

    allow(client).to receive(:update_session) do |_session, config:, apps:|
      update_calls += 1
      if update_calls == 1
        remote_session['status'] = 'STOPPED'
        remote_session['config'] = config.deep_dup
        # Simulates WAHA having already updated the first App before a later App fails.
        remote_apps[0] = apps.find { |app| app['id'] == 'app_123' }.deep_dup
        raise Waha::Client::Error, 'provider failed after partial write'
      end

      remote_session['config'] = config.deep_dup
      remote_session['status'] = 'STOPPED'
      remote_apps.replace(apps.deep_dup)
      remote_session.merge('apps' => remote_apps.deep_dup)
    end

    result = service.perform(apply: true)

    expect(result.to_h.slice(:failed, :recovered, :recovery_failed, :halted)).to eq(
      failed: 1, recovered: 1, recovery_failed: 0, halted: true
    )
    expect(update_calls).to eq(2)
    expect(client).to have_received(:start_session).with('5511999999999').once
    expect(remote_session.slice('status', 'config')).to eq('status' => 'WORKING', 'config' => original_config)
    expect(remote_apps).to eq(original_apps)
    expect([inbox.reload.lock_to_single_conversation, channel.reload.additional_attributes['phone_numbers_app_id']])
      .to eq([false, nil])
    expect(output.string).to include('RECOVERED')
  end

  it 'rolls back when WAHA never returns to WORKING after the desired update' do
    original_apps = remote_apps.deep_dup
    update_calls = 0

    allow(client).to receive(:update_session) do |_session, config:, apps:|
      update_calls += 1
      remote_session['config'] = config.deep_dup
      remote_apps.replace(apps.deep_dup)
      remote_session['status'] = 'STARTING'
      remote_session.merge('apps' => remote_apps.deep_dup)
    end
    allow(client).to receive(:start_session) do
      remote_session['status'] = 'WORKING'
      remote_session.deep_dup
    end

    result = service.perform(apply: true)

    expect(result.failed).to eq(1)
    expect(result.recovered).to eq(1)
    expect(result.halted).to be(true)
    expect(update_calls).to eq(2)
    expect(remote_apps).to eq(original_apps)
    expect(remote_session['status']).to eq('WORKING')
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end

  it 'marks recovery failure as critical and halts without local writes' do
    update_calls = 0

    allow(client).to receive(:update_session) do |_session, config:, apps:|
      update_calls += 1
      remote_session['status'] = 'STOPPED'
      remote_session['config'] = config.deep_dup
      remote_apps.replace(apps.deep_dup)
      raise Waha::Client::Error, update_calls == 1 ? 'desired update failed' : 'rollback failed'
    end

    result = service.perform(apply: true)

    expect(result.failed).to eq(1)
    expect(result.recovered).to eq(0)
    expect(result.recovery_failed).to eq(1)
    expect(result.halted).to be(true)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
    expect(output.string).to include('CRITICAL')
  end

  it 'does not process a second inbox after the first apply failure' do
    second_channel = create(
      :channel_api,
      account: account,
      additional_attributes: {
        'provider' => 'waha',
        'session' => '5511888888888',
        'app_id' => 'app_second'
      }
    )
    second_channel.inbox.update!(lock_to_single_conversation: false)

    allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'first failed')

    result = service.perform(apply: true)

    expect(result.total).to eq(1)
    expect(result.failed).to eq(1)
    expect(result.halted).to be(true)
    expect(client).not_to have_received(:get_app).with('app_second')
  end

  it 'skips a remote Chatwoot app that does not match the stored session' do
    remote_app['session'] = 'another-session'
    remote_apps.replace([remote_app.deep_dup])

    result = service.perform(apply: true)

    expect(result.skipped).to eq(1)
    expect(result.halted).to be(true)
    expect(client).not_to have_received(:update_session)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end
end
