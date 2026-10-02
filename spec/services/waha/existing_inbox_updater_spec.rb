require 'rails_helper'

RSpec.describe Waha::ExistingInboxUpdater do
  let(:account) { create(:account) }
  let(:client) { instance_double(Waha::Client) }
  let(:output) { StringIO.new }
  let(:service) { described_class.new(client: client, output: output) }
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
  let(:session_info) do
    {
      'name' => '5511999999999',
      'config' => { 'ignore' => { 'status' => true, 'groups' => true } }
    }
  end

  before do
    allow(client).to receive(:get_app).with('app_123') { remote_app.deep_dup }
    allow(client).to receive(:get_session).with('5511999999999') { session_info.deep_dup }
    allow(client).to receive(:list_apps).with('5511999999999') do
      [remote_app.deep_dup, remote_phone_app&.deep_dup, remote_other_app&.deep_dup].compact
    end
    allow(client).to receive(:update_session)
  end

  it 'is dry-run by default and reports all required changes without writing' do
    result = service.perform

    expect(result.would_update).to eq(1)
    expect(result.updated).to eq(0)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
    expect(client).not_to have_received(:update_session)
    expect(output.string).to include('brazilian_phone_numbers_app')
    expect(output.string).to include('DRY_RUN')
  end

  it 'updates Chatwoot, creates the Brazilian resolver and records its app id' do
    result = service.perform(apply: true)

    expect(result.updated).to eq(1)
    expect(inbox.reload.lock_to_single_conversation).to be(true)

    phone_app_id = channel.reload.additional_attributes['phone_numbers_app_id']
    expect(phone_app_id).to start_with('br_')
    expect(client).to have_received(:update_session).with(
      '5511999999999',
      config: session_info['config'],
      apps: contain_exactly(
        hash_including(
          'id' => phone_app_id,
          'app' => 'brazilian-phone-numbers',
          'enabled' => true,
          'config' => hash_including(
            'strict' => false,
            'lookup' => true,
            'cache' => hash_including(
              'memoryTtl' => '24h',
              'persistent' => true,
              'persistentTtl' => '31d'
            )
          )
        ),
        hash_including(
          'id' => 'app_123',
          'config' => hash_including(
            'groups' => 'OFF',
            'customFutureOption' => { 'keep' => true },
            'conversations' => hash_including(
              'markAsRead' => true,
              'sort' => 'created_newest',
              'status' => nil,
              'outgoing' => 'message',
              'syncMessageStatus' => true
            )
          )
        )
      )
    ).once
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

    it 'preserves the unrelated app while syncing Chatwoot and the Brazilian resolver' do
      service.perform(apply: true)

      expect(client).to have_received(:update_session).with(
        '5511999999999',
        config: session_info['config'],
        apps: array_including(remote_other_app)
      ).once
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

    it 'is idempotent when both remote apps and the local inbox are already compliant' do
      inbox.update!(lock_to_single_conversation: true)
      channel.update!(
        additional_attributes: channel.additional_attributes.merge('phone_numbers_app_id' => 'br_existing')
      )
      remote_app['config']['conversations'].merge!(
        'outgoing' => 'message',
        'syncMessageStatus' => true
      )

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

      service.perform(apply: true)

      expect(client).to have_received(:update_session).with(
        '5511999999999',
        config: session_info['config'],
        apps: array_including(
          hash_including(
            'id' => 'br_existing',
            'enabled' => true,
            'config' => hash_including(
              'lookup' => true,
              'strict' => false,
              'customFutureOption' => { 'keep' => true },
              'cache' => hash_including('persistent' => true)
            )
          )
        )
      ).once
      expect(channel.reload.additional_attributes['phone_numbers_app_id']).to eq('br_existing')
    end
  end

  it 'does not change local state when the remote session update fails' do
    allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'provider failed')

    result = service.perform(apply: true)

    expect(result.failed).to eq(1)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(channel.reload.additional_attributes['phone_numbers_app_id']).to be_nil
  end

  it 'skips a remote Chatwoot app that does not match the stored session' do
    remote_app['session'] = 'another-session'

    result = service.perform(apply: true)

    expect(result.skipped).to eq(1)
    expect(client).not_to have_received(:update_session)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end
end
