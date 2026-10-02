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

  before do
    allow(client).to receive(:get_app).with('app_123') { remote_app.deep_dup }
    allow(client).to receive(:update_app)
  end

  it 'is dry-run by default and reports without writing' do
    result = service.perform

    expect(result.would_update).to eq(1)
    expect(result.updated).to eq(0)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
    expect(client).not_to have_received(:update_app)
    expect(output.string).to include('DRY_RUN')
  end

  it 'updates only the new Chatwoot conversation options and preserves existing config' do
    result = service.perform(apply: true)

    expect(result.updated).to eq(1)
    expect(inbox.reload.lock_to_single_conversation).to be(true)
    expect(client).to have_received(:update_app).with(
      'app_123',
      hash_including(
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
    ).once
  end

  it 'is idempotent when the remote app and local inbox are already compliant' do
    inbox.update!(lock_to_single_conversation: true)
    remote_app['config']['conversations'].merge!(
      'outgoing' => 'message',
      'syncMessageStatus' => true
    )

    result = service.perform(apply: true)

    expect(result.unchanged).to eq(1)
    expect(result.updated).to eq(0)
    expect(client).not_to have_received(:update_app)
    expect(output.string).to include('already compliant')
  end

  it 'does not change the local inbox when the remote update fails' do
    allow(client).to receive(:update_app).and_raise(Waha::Client::Error, 'provider failed')

    result = service.perform(apply: true)

    expect(result.failed).to eq(1)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end

  it 'skips a remote app that does not match the stored session' do
    remote_app['session'] = 'another-session'

    result = service.perform(apply: true)

    expect(result.skipped).to eq(1)
    expect(client).not_to have_received(:update_app)
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end
end
