require 'rails_helper'

RSpec.describe Waha::HistoryImporter do
  let(:account) { create(:account) }
  let(:cutoff) { 1.minute.ago.to_i }
  let(:chat_id) { '16505551234@c.us' }
  let(:channel) do
    create(:channel_api, account: account, additional_attributes: {
             'provider' => 'waha', 'session' => 'test-session',
             'waha_history_import' => { 'before' => cutoff, 'status' => 'running' }
           })
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }
  let(:importer) { described_class.new(inbox: inbox, client: client, before: cutoff) }
  let(:incoming) do
    { 'id' => 'false_16505551234@c.us_OLD1', 'timestamp' => 2.years.ago.to_i,
      'fromMe' => false, 'body' => 'Mensagem anterior', 'hasMedia' => false }
  end
  let(:outgoing) { incoming.merge('id' => 'true_16505551234@c.us_OLD2', 'fromMe' => true, 'timestamp' => 1.year.ago.to_i) }

  before do
    inbox.update!(lock_to_single_conversation: true)
    allow(client).to receive(:get_lid_mapping).with('test-session', chat_id: chat_id).and_return('pn' => chat_id, 'lid' => nil)
    allow(client).to receive(:get_contact).with('test-session', contact_id: chat_id).and_return('name' => 'Contato histórico')
  end

  it 'imports available history older than six months with original dates, direction and public visibility' do
    expect(importer.import(chat_id: chat_id, messages: [incoming, outgoing])).to eq(imported: 2, unavailable_media: 0)

    messages = inbox.messages.reload
    records = messages.map do |message|
      [message.created_at.to_i, message.message_type, message.status, message.private?, message.source_id]
    end
    expected = [
      [incoming['timestamp'], 'incoming', 'read', false, incoming['id']],
      [outgoing['timestamp'], 'outgoing', 'delivered', false, outgoing['id']]
    ]
    expect(records).to eq(expected)
    expect(inbox.conversations.last).to be_resolved
    expect(inbox.conversations.last.waiting_since).to be_nil
    expect(inbox.conversations.last.unread_incoming_messages).to be_empty
    expect(inbox.conversations.last.created_at).to be > Time.zone.at(cutoff)
  end

  it 'does not send replies, dispatch events, assign bots or create CRM/reporting/notifications' do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot))
    account.enable_features!('ip_lookup')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    clear_enqueued_jobs

    importer.import(chat_id: chat_id, messages: [incoming, outgoing])

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(
      SendReplyJob, EventDispatcherJob, ContactIpLookupJob, AutoAssignment::AssignmentJob
    )
    conversation = inbox.conversations.last
    expect([conversation.ai_assignee, conversation.assignee]).to eq([nil, nil])
    expect([conversation.notifications.count, conversation.crm_cards.count, conversation.reporting_events.count]).to eq([0, 0, 0])
    expect([Current.waha_history_import, Current.suppress_contact_events]).to eq([nil, nil])
  end

  it 'reuses a live contact/thread and preserves its status, assignee and unread live messages' do
    contact = create(:contact, account: account, phone_number: '+16505551234',
                               custom_attributes: { 'waha_whatsapp_chat_id' => chat_id })
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: 'native-public-source')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                         contact_inbox: contact_inbox, status: :snoozed,
                                         snoozed_until: 1.day.from_now, agent_last_seen_at: nil)
    live = create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact,
                            message_type: :incoming, created_at: Time.zone.at(cutoff - 30))
    conversation.update!(status: :snoozed, snoozed_until: 1.day.from_now)

    expect { importer.import(chat_id: chat_id, messages: [incoming]) }.not_to change(ContactInbox, :count)
    expect(conversation.reload).to be_snoozed
    expect(conversation.messages.count).to eq(2)
    expect([conversation.agent_last_seen_at, conversation.unread_incoming_messages]).to eq([nil, [live]])
    expect(ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform.id).to eq(conversation.id)
  end

  it 'deduplicates repeated/out-of-order pages within the inbox and preserves imports in another inbox' do
    importer.import(chat_id: chat_id, messages: [outgoing, incoming])
    expect(importer.import(chat_id: chat_id, messages: [incoming, outgoing])).to eq(imported: 0, unavailable_media: 0)

    other = create(:channel_api, account: account, additional_attributes: channel.additional_attributes).inbox
    other.update!(lock_to_single_conversation: true)
    described_class.new(inbox: other, client: client, before: cutoff).import(chat_id: chat_id, messages: [incoming])

    expect(inbox.messages.count).to eq(2)
    expect(other.messages.count).to eq(1)
  end

  it 'leaves existing boxes without the new marker untouched' do
    channel.update!(additional_attributes: { 'provider' => 'waha', 'session' => 'test-session' })
    inbox.reload
    expect { importer.import(chat_id: chat_id, messages: [incoming]) }.to raise_error(described_class::InvalidHistory)
    expect(inbox.messages).to be_empty
    expect(client).not_to have_received(:get_contact)
  end

  it 'deduplicates the same WhatsApp id repeated within a single page' do
    expect(importer.import(chat_id: chat_id, messages: [incoming, incoming])).to eq(imported: 1, unavailable_media: 0)
    expect(inbox.messages.count).to eq(1)
  end

  it 'uses the WhatsApp pushname when no address-book name exists' do
    allow(client).to receive(:get_contact).and_return('pushname' => 'Nome do WhatsApp')
    importer.import(chat_id: chat_id, messages: [incoming])
    expect(inbox.conversations.last.contact.name).to eq('Nome do WhatsApp')
  end

  it 'waits for a panel send identity and then recognizes every WhatsApp attachment part' do
    contact = create(:contact, account: account, phone_number: '+16505551234')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: chat_id)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    panel_message = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: false,
      status: :failed
    )
    file_id = 'true_16505551234@c.us_FILE2'
    rows = [outgoing, outgoing.merge('id' => file_id)]

    expect { importer.import(chat_id: chat_id, messages: rows) }.to raise_error(Waha::Client::Error, 'history_outbound_pending')
    expect(inbox.messages.outgoing.count).to eq(1)

    Waha::MessageSourceIds.new(message: panel_message, source_ids: [outgoing['id'], file_id]).perform

    expect(importer.import(chat_id: chat_id, messages: rows)).to eq(imported: 0, unavailable_media: 0)
    expect(inbox.messages.outgoing.count).to eq(1)
  end

  it 'keeps history-only conversations and messages out of reports until live activity starts' do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot))
    importer.import(chat_id: chat_id, messages: [incoming, outgoing])
    range = 5.years.ago..1.day.from_now
    params = { type: :account, since: range.begin, until: range.end }
    source = Reports::RawDataSource.new(account: account, scope: account, range: range, metric: 'conversations_count')

    expect([source.aggregate, source.summary.values.sum { |row| row[:conversations_count] }]).to eq([0, 0])
    expect(V2::ReportBuilder.new(account, params).summary).to include(
      conversations_count: 0, incoming_messages_count: 0, outgoing_messages_count: 0
    )
    expect([
             V2::Reports::ChannelSummaryBuilder.new(account: account, params: params).build,
             V2::Reports::OutgoingMessagesCountBuilder.new(account, params.merge(group_by: 'inbox')).build
           ]).to eq([{}, []])
    expect(V2::Reports::BotMetricsBuilder.new(account, params).metrics).to include(conversation_count: 0, message_count: 0)

    conversation = inbox.conversations.last
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.contact, message_type: :incoming)

    expect(source.aggregate).to eq(1)
    expect(V2::ReportBuilder.new(account, params).summary).to include(
      conversations_count: 1, incoming_messages_count: 1, outgoing_messages_count: 0
    )
    live_counts = [
      V2::Reports::ChannelSummaryBuilder.new(account: account, params: params).build['Channel::Api'][:total],
      V2::Reports::BotMetricsBuilder.new(account, params).metrics[:conversation_count]
    ]
    expect(live_counts).to eq([1, 1])
  end

  it 'records the first live response even with multiple historical outgoing messages and a later first contact' do
    importer.import(chat_id: chat_id, messages: [incoming, outgoing, outgoing.merge('id' => 'true_16505551234@c.us_OLD3')])
    conversation = inbox.conversations.last
    user = create(:user, account: account)
    live_at = 3.hours.from_now.change(usec: 0)
    travel_to(live_at) do
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       sender: conversation.contact, message_type: :incoming)
    end
    reply = nil
    travel_to(live_at + 2.minutes) do
      reply = create(:message, conversation: conversation, account: account, inbox: inbox, sender: user, message_type: :outgoing)
    end
    event = Events::Base.new('first.reply.created', reply.created_at, message: reply)
    ReportingEventListener.instance.first_reply_created(event)

    expect(conversation.reload.first_reply_created_at).to eq(reply.created_at)
    expect(conversation.created_at).to eq(live_at)
    expect(conversation.additional_attributes).not_to have_key('waha_history_only')
    expect(conversation.reporting_events.find_by!(name: 'first_response').value).to eq(120)
    expect(conversation.messages.where(source_id: incoming['id']).first.created_at.to_i).to eq(incoming['timestamp'])
  end

  it 'reuses the Brazilian contact and inbox when WhatsApp omits its ninth digit' do
    brazilian_chat = '551198765432@c.us'
    contact = create(:contact, account: account, phone_number: '+5511998765432')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact)
    allow(client).to receive(:get_lid_mapping).with('test-session', chat_id: brazilian_chat).and_return('pn' => brazilian_chat, 'lid' => nil)
    allow(client).to receive(:get_contact).with('test-session', contact_id: brazilian_chat).and_return('name' => 'Contato histórico')

    expect do
      importer.import(chat_id: brazilian_chat, messages: [incoming.merge('id' => 'false_551198765432@c.us_OLD')])
    end.not_to change(Contact, :count)
    expect(inbox.conversations.last.contact_inbox_id).to eq(contact_inbox.id)
  end

  it 'rejects messages after the immutable onboarding cutoff before any local write' do
    expect do
      importer.import(chat_id: chat_id, messages: [incoming.merge('timestamp' => cutoff + 1)])
    end.to raise_error(described_class::InvalidHistory)
    expect(inbox.messages).to be_empty
    expect(inbox.conversations).to be_empty
  end

  it 'rolls back the entire message page on validation failure and restores Current flags' do
    expect do
      importer.import(chat_id: chat_id, messages: [incoming, outgoing.merge('body' => 'a' * 150_001)])
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(inbox.messages).to be_empty
    expect(inbox.conversations).to be_empty
    expect(Current.waha_history_import).to be_nil
    expect(Current.suppress_contact_events).to be_nil
  end

  it 'imports a downloadable media asset and marks unavailable media explicitly' do
    media = incoming.merge('hasMedia' => true)
    file = Tempfile.new(['history', '.png'])
    file.binmode
    file.write(File.binread(Rails.root.join('spec/assets/avatar.png')))
    file.rewind
    allow(client).to receive(:get_message).and_return('media' => { 'url' => 'https://waha.example/api/files/image.png', 'mimetype' => 'image/png' })
    allow(client).to receive(:download_media).and_return(file)

    importer.import(chat_id: chat_id, messages: [media])
    expect(inbox.messages.last.attachments.last.file).to be_attached

    allow(client).to receive(:get_message).and_return('media' => nil)
    result = importer.import(chat_id: chat_id, messages: [outgoing.merge('hasMedia' => true)])
    expect(result).to eq(imported: 1, unavailable_media: 1)
    expect(inbox.messages.last.content_attributes['is_history_media_placeholder']).to be(true)
  end

  it 'matches LID and phone identities instead of opening a second customer thread' do
    contact = create(:contact, account: account, phone_number: '+16505551234')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact)
    lid = '12345@lid'
    allow(client).to receive(:get_lid_mapping).with('test-session', chat_id: lid).and_return('pn' => chat_id, 'lid' => lid)

    expect { importer.import(chat_id: lid, messages: [incoming]) }.not_to change(Contact, :count)
    expect(inbox.conversations.last.contact_inbox_id).to eq(contact_inbox.id)
  end
end
