require 'rails_helper'
require 'timeout'

RSpec.describe Waha::MessageSourceIds do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_api,
      account: account,
      additional_attributes: { 'provider' => 'waha', 'waha_history_import' => { 'status' => 'completed' } }
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'contact@c.us') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:source_ids) { %w[waha-id-1 waha-id-2] }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: contact,
      additional_attributes: { 'keep' => 'value' },
      source_id: nil
    )
  end

  def perform
    described_class.new(message: message, source_ids: source_ids).perform
  end

  it 'stores every source ID, captures the first one and preserves other attributes' do
    result = perform

    expect(result.reload.source_id).to eq(source_ids.first)
    expect(result.additional_attributes).to include('keep' => 'value', 'waha_source_ids' => source_ids)
  end

  context 'when the message already has the exact identity' do
    let(:message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        source_id: source_ids.first,
        additional_attributes: { 'keep' => 'value', 'waha_source_ids' => source_ids }
      )
    end

    it 'does not save or dispatch an update' do
      message
      dispatcher = Rails.configuration.dispatcher
      allow(dispatcher).to receive(:dispatch)
      expect(message).not_to receive(:save!)

      result = perform

      expect(result).to eq(message)
      expect(dispatcher).not_to have_received(:dispatch)
    end
  end

  context 'when the existing identity differs' do
    let(:message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        source_id: source_ids.first,
        additional_attributes: { 'keep' => 'value', 'waha_source_ids' => ['old-waha-id'] }
      )
    end

    it 'fails without changing the message' do
      message
      expect(message).not_to receive(:save!)

      expect { perform }.to raise_error(described_class::IdentityConflict, 'waha_message_identity_conflict')
      expect(message.reload.source_id).to eq(source_ids.first)
      expect(message.additional_attributes['waha_source_ids']).to eq(['old-waha-id'])
    end
  end

  context 'when source_id is already set to another ID' do
    let(:message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        source_id: 'already-linked',
        additional_attributes: { 'keep' => 'value' }
      )
    end

    it 'fails before writing' do
      message
      expect(message).not_to receive(:save!)

      expect { perform }.to raise_error(described_class::IdentityConflict, 'waha_message_identity_conflict')
    end
  end

  context 'when a source ID belongs to another message in the same inbox' do
    let(:other_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        source_id: source_ids.first
      )
    end

    it 'fails without writing' do
      other_message
      message
      expect(message).not_to receive(:save!)

      expect { perform }.to raise_error(described_class::IdentityConflict, 'waha_message_identity_conflict')
    end
  end

  context 'when a source ID is captured by another message in the same inbox' do
    let(:other_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: contact,
        additional_attributes: { 'waha_source_ids' => [source_ids.second] },
        source_id: nil
      )
    end

    it 'checks the captured array as well as source_id' do
      other_message
      expect { perform }.to raise_error(described_class::IdentityConflict, 'waha_message_identity_conflict')
    end
  end

  it 'does not treat an identity in another inbox as a conflict' do
    other_channel = create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' })
    other_inbox = other_channel.inbox
    other_contact_inbox = create(:contact_inbox, contact: contact, inbox: other_inbox, source_id: 'other@c.us')
    other_conversation = create(
      :conversation,
      account: account,
      inbox: other_inbox,
      contact: contact,
      contact_inbox: other_contact_inbox
    )
    create(
      :message,
      account: account,
      inbox: other_inbox,
      conversation: other_conversation,
      sender: contact,
      source_id: source_ids.first
    )

    expect { perform }.not_to raise_error
    expect(message.reload.source_id).to eq(source_ids.first)
  end

  context 'when two contact inboxes race in one inbox', :relationships_committed_fixtures do
    self.use_transactional_tests = false

    let!(:second_contact) { create(:contact, account: account, name: 'Second') }
    let!(:second_contact_inbox) do
      create(:contact_inbox, contact: second_contact, inbox: inbox, source_id: 'second@c.us')
    end
    let!(:second_conversation) do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: second_contact,
        contact_inbox: second_contact_inbox
      )
    end
    let!(:second_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: second_conversation,
        sender: second_contact,
        additional_attributes: { 'keep' => 'second' },
        source_id: nil
      )
    end
    let(:concurrency) do
      { workers: [], first_update_ready: Queue.new, release_first_update: Queue.new }
    end
    let(:update_barrier) do
      ready = concurrency.fetch(:first_update_ready)
      release = concurrency.fetch(:release_first_update)
      proc do
        next unless Thread.current[:waha_source_ids_writer] == :first

        ready << true
        release.pop
      end
    end

    before { Message.set_callback(:update, :before, update_barrier) }

    after do
      concurrency.fetch(:release_first_update) << true
      concurrency.fetch(:workers).each { |worker| worker.join(1) || worker.kill.join }
      Message.skip_callback(:update, :before, update_barrier)
      channel.update!(additional_attributes: {})
      inbox.messages.destroy_all
      inbox.conversations.destroy_all
      inbox.contact_inboxes.destroy_all
      inbox.destroy!
      account.contacts.destroy_all
      account.destroy!
    end

    def run_in_database_worker(message, writer, ids)
      ready = Queue.new
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '10s'")
          ready << connection.select_value('SELECT pg_backend_pid()')
          Thread.current[:waha_source_ids_writer] = writer
          result = Waha::MessageSourceIds.new(message: Message.find(message.id), source_ids: ids).perform
          [:updated, result.id]
        rescue Waha::MessageSourceIds::IdentityConflict => e
          [:conflict, e.message]
        ensure
          Thread.current[:waha_source_ids_writer] = nil
          connection.execute('SET lock_timeout TO DEFAULT')
        end
      end
      concurrency.fetch(:workers) << worker
      [worker, Timeout.timeout(10) { ready.pop }]
    end

    def wait_for_block(worker, pid, blocker_pid)
      Timeout.timeout(10) do
        loop do
          return true if ActiveRecord::Base.connection.select_value(
            "SELECT #{Integer(blocker_pid)} = ANY(pg_blocking_pids(#{Integer(pid)}))"
          )
          return false unless worker.alive?

          sleep 0.01
        end
      end
    end

    it 'serializes the same source IDs across different contact inboxes in one PostgreSQL transaction', :aggregate_failures do
      ids = source_ids
      first_worker, first_pid = run_in_database_worker(message, :first, ids)
      Timeout.timeout(10) { concurrency.fetch(:first_update_ready).pop }
      second_worker, second_pid = run_in_database_worker(second_message, :second, ids)

      expect(wait_for_block(second_worker, second_pid, first_pid)).to be(true)
      concurrency.fetch(:release_first_update) << true
      expect([first_worker.join(15), second_worker.join(15)]).to eq([first_worker, second_worker])
      outcomes = [first_worker.value, second_worker.value]

      expect(outcomes.count { |outcome| outcome.first == :updated }).to eq(1)
      expect(outcomes.count { |outcome| outcome.first == :conflict }).to eq(1)
      expect(message.reload.source_id).to eq(ids.first)
      expect(second_message.reload.source_id).to be_nil
      expect(second_message.additional_attributes).not_to have_key('waha_source_ids')
      expect(inbox.messages.where(source_id: ids.first).count).to eq(1)
      expect(inbox.messages.where("additional_attributes->'waha_source_ids' @> ?::jsonb", [ids.second].to_json).count).to eq(1)
    end
  end
end
