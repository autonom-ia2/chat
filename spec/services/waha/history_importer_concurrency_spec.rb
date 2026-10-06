require 'rails_helper'
require 'timeout'

RSpec.describe Waha::HistoryImporter, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let(:cutoff) { 1.minute.ago.to_i }
  let(:chat_id) { '16505551234@c.us' }
  let!(:channel) do
    create(:channel_api, account: account, additional_attributes: {
             'provider' => 'waha', 'session' => 'test-session',
             'waha_history_import' => { 'status' => 'running', 'before' => cutoff }
           })
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }
  let(:blocked_kind) { nil }
  let(:queues) do
    { ready: Queue.new, release: Queue.new, message_ready: Queue.new, message_release: Queue.new, workers: [] }
  end
  let(:barrier) do
    signal = queues[:ready]
    gate = queues[:release]
    proc do
      if Current.waha_history_import && phone_number == '+16505551234'
        signal << true
        gate.pop
      end
    end
  end

  let(:message_barrier) do
    signal = queues[:message_ready]
    gate = queues[:message_release]
    target = blocked_kind
    proc do
      next unless target && Thread.current[:waha_message_writer] == target

      signal << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
      gate.pop
    end
  end

  before do
    inbox.update!(lock_to_single_conversation: true)
    allow(client).to receive(:get_lid_mapping).and_return('pn' => chat_id, 'lid' => nil)
    allow(client).to receive(:get_contact).and_return('name' => 'History contact')
    Contact.set_callback(:validation, :after, barrier)
    Message.set_callback(:create, :before, message_barrier)
  end

  after do
    queues[:release] << true
    queues[:message_release] << true
    queues[:workers].each { |worker| worker.join(2) || worker.kill.join }
    Contact.skip_callback(:validation, :after, barrier)
    Message.skip_callback(:create, :before, message_barrier)
    channel.update!(additional_attributes: {})
    inbox.messages.destroy_all
    inbox.conversations.destroy_all
    inbox.contact_inboxes.destroy_all
    inbox.destroy!
    account.contacts.destroy_all
    account.destroy!
  end

  def database_worker(writer)
    ready = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '10s'")
        ready << connection.select_value('SELECT pg_backend_pid()')
        Thread.current[:waha_message_writer] = writer
        yield
      ensure
        Thread.current[:waha_message_writer] = nil
        connection.execute('SET lock_timeout TO DEFAULT')
      end
    end
    queues[:workers] << worker
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

  def historical_payload(source_id)
    { 'id' => source_id, 'timestamp' => 1.year.ago.to_i, 'body' => 'History', 'fromMe' => false, 'hasMedia' => false }
  end

  def native_message_id(conversation_id, source_id)
    params = ActionController::Parameters.new(content: 'Native', message_type: 'incoming', source_id: source_id)
    Messages::MessageBuilder.new(nil, Conversation.find(conversation_id), params).perform.id
  end

  it 'serializes real PostgreSQL writers and keeps a single contact/thread while the live message remains unread' do
    id = inbox.id
    history = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.new(inbox: Inbox.find(id), client: client, before: cutoff).import(
          chat_id: chat_id,
          messages: [{ 'id' => 'false_16505551234@c.us_HIST', 'timestamp' => 1.year.ago.to_i,
                       'body' => 'History', 'fromMe' => false, 'hasMedia' => false }]
        )
      end
    end
    queues[:workers] << history
    Timeout.timeout(10) { queues[:ready].pop }
    live_pid = Queue.new
    live = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '10s'")
        live_pid << connection.select_value('SELECT pg_backend_pid()')
        contact_inbox = ContactInboxWithContactBuilder.new(
          inbox: Inbox.find(id), source_id: 'native-live-source',
          contact_attributes: { phone_number: '+16505551234', name: 'Live contact',
                                custom_attributes: { 'waha_whatsapp_chat_id' => chat_id } }
        ).perform
        conversation = ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
        conversation.messages.create!(account_id: account.id, inbox_id: id, sender: contact_inbox.contact,
                                      message_type: :incoming, content: 'Live')
      ensure
        connection.execute('SET lock_timeout TO DEFAULT')
      end
    end
    queues[:workers] << live
    pid = Timeout.timeout(10) { live_pid.pop }
    blocked = Timeout.timeout(10) do
      loop do
        break true if ActiveRecord::Base.connection.select_value("SELECT cardinality(pg_blocking_pids(#{Integer(pid)})) > 0")
        break false unless live.alive?

        sleep 0.01
      end
    end
    queues[:release] << true
    expect(queues[:workers].map { |worker| worker.join(15) }).to eq(queues[:workers])
    queues[:workers].each(&:value)

    expect(blocked).to be(true)
    expect([account.contacts.count, inbox.contact_inboxes.count, inbox.conversations.count, inbox.messages.count]).to eq([1, 1, 1, 2])
    expect(inbox.conversations.last.unread_incoming_messages.map(&:content)).to eq(['Live'])
  end

  context 'when history and native writes share a ContactInbox' do
    let(:blocked_kind) { :history }
    let(:shared_source_id) { 'false_16505551234@c.us_SHARED' }
    let!(:contact) do
      create(:contact, account: account, phone_number: '+16505551234',
                       custom_attributes: { 'waha_whatsapp_chat_id' => chat_id })
    end
    let!(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: chat_id) }
    let!(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                            status: :resolved, additional_attributes: { 'waha_history_only' => true })
    end

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      clear_enqueued_jobs
    end

    it 'lets native return the history row after history commits first' do
      history, history_pid = database_worker(:history) do
        described_class.new(inbox: Inbox.find(inbox.id), client: client, before: cutoff).import(
          chat_id: chat_id, messages: [historical_payload(shared_source_id)]
        )
      end
      expect(Timeout.timeout(10) { queues[:message_ready].pop }).to eq(history_pid)

      native, native_pid = database_worker(:native) do
        native_message_id(conversation.id, shared_source_id)
      end
      expect(wait_for_block(native, native_pid, history_pid)).to be(true)

      queues[:message_release] << true
      expect([history.join(15), native.join(15)]).to eq([history, native])

      message = inbox.messages.find_by!(source_id: shared_source_id)
      expect([history.value, native.value]).to eq([{ imported: 1, unavailable_media: 0 }, message.id])
      expect(
        [
          inbox.messages.where(source_id: shared_source_id).count,
          message.content,
          conversation.reload.additional_attributes['waha_history_only']
        ]
      ).to eq([1, 'History', true])
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      expect(enqueued_jobs.map { |job| job[:job] }).not_to include(SendReplyJob)
    end

    context 'when native obtains the lock first' do
      let(:blocked_kind) { :native }

      it 'keeps the native row when history finds it' do
        # The callback holds the ContactInbox lock after native has written its row but before commit.
        native, native_pid = database_worker(:native) do
          native_message_id(conversation.id, shared_source_id)
        end
        expect(Timeout.timeout(10) { queues[:message_ready].pop }).to eq(native_pid)

        history, history_pid = database_worker(:history) do
          described_class.new(inbox: Inbox.find(inbox.id), client: client, before: cutoff).import(
            chat_id: chat_id, messages: [historical_payload(shared_source_id)]
          )
        end
        expect(wait_for_block(history, history_pid, native_pid)).to be(true)

        queues[:message_release] << true
        expect([native.join(15), history.join(15)]).to eq([native, history])

        native_id = native.value
        expect(history.value).to eq(imported: 0, unavailable_media: 0)
        message = inbox.messages.find_by!(source_id: shared_source_id)
        expect([native_id, message.id, message.content, inbox.messages.where(source_id: shared_source_id).count]).to eq(
          [native_id, native_id, 'Native', 1]
        )
        expect(inbox.conversations.count).to eq(1)
      end
    end
  end
end
