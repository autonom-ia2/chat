# Historical writes retain original dates and never enter the live reply pipeline.
class Waha::HistoryImporter
  include CampaignImports::SuppressedContactEvents
  include FileTypeHelper

  InvalidHistory = Class.new(StandardError)

  def initialize(inbox:, client:, before:)
    @inbox = inbox
    @client = client
    @before = before
    @session = inbox.channel.additional_attributes.fetch('session')
  end

  def import(chat_id:, messages:)
    @downloaded_files = []
    validate_import!(chat_id)
    rows = messages.map { |message| prepare_message(chat_id, message) }
    return { imported: 0, unavailable_media: 0 } if rows.empty?

    attributes = contact_attributes(chat_id)
    with_history_context do
      contact_inbox = ContactInboxWithContactBuilder.new(inbox: @inbox, source_id: chat_id, contact_attributes: attributes).perform
      write_page(contact_inbox, rows)
    end
  ensure
    @downloaded_files&.each(&:close!)
  end

  private

  def validate_import!(chat_id)
    marker = @inbox.channel.additional_attributes['waha_history_import']
    raise InvalidHistory, 'history_not_enabled_for_this_connection' unless marker && marker['before'] == @before
    raise InvalidHistory, 'history_requires_single_conversation' unless @inbox.lock_to_single_conversation?
    raise InvalidHistory, 'history_requires_direct_chat' unless chat_id.end_with?('@c.us', '@s.whatsapp.net', '@lid')
  end

  def with_history_context(&)
    previous = Current.waha_history_import
    Current.waha_history_import = true
    with_suppressed_contact_events(&)
  ensure
    Current.waha_history_import = previous
  end

  def prepare_message(chat_id, message)
    validate_message!(message)
    row = { payload: message, file: nil, unavailable_media: false }
    return row unless message['hasMedia'] == true
    return row if @inbox.messages.with_waha_source_id(message['id']).exists?

    prepare_media(chat_id, row)
  end

  def validate_message!(message)
    timestamp = message.fetch('timestamp')
    unless message['id'].is_a?(String) && message['id'].present? && timestamp.is_a?(Integer) && timestamp.positive? &&
           timestamp <= @before && [true, false].include?(message['fromMe'])
      raise InvalidHistory, 'invalid_historical_message'
    end
  end

  def prepare_media(chat_id, row)
    downloaded = @client.get_message(@session, chat_id: chat_id, message_id: row[:payload]['id'])
    media = downloaded['media']
    if media.is_a?(Hash) && media['url'].present?
      row[:file] = @client.download_media(media['url'])
      @downloaded_files << row[:file]
      row[:mimetype] = media['mimetype']
      row[:url] = media['url']
    else
      row[:unavailable_media] = true
    end
    row
  rescue Waha::Client::Error => e
    raise unless e.status == 404

    row[:unavailable_media] = true
    row
  rescue Down::NotFound, Down::TooLarge
    row[:unavailable_media] = true
    row
  end

  def contact_attributes(chat_id)
    jid, lid = contact_identity(chat_id)
    contact = contact_info(jid || chat_id)
    phone = phone_number(jid)
    {
      identifier: phone ? nil : chat_id, phone_number: phone,
      name: (contact['name'].presence || contact['pushname'].presence || phone || chat_id).truncate(255),
      custom_attributes: { 'waha_whatsapp_chat_id' => chat_id, 'waha_whatsapp_jid' => jid, 'waha_whatsapp_lid' => lid }.compact
    }
  end

  def contact_info(chat_id)
    @client.get_contact(@session, contact_id: chat_id)
  rescue Waha::Client::Error => e
    raise unless e.status == 404

    {} # A stored chat can outlive its contact/profile entry in WhatsApp.
  end

  def contact_identity(chat_id)
    mapping = @client.get_lid_mapping(@session, chat_id: chat_id)
    jid = mapping['pn'].presence || (chat_id unless chat_id.end_with?('@lid'))
    lid = mapping['lid'].presence || (chat_id if chat_id.end_with?('@lid'))
    [jid, lid]
  end

  def phone_number(jid)
    digits = jid&.split('@')&.first
    "+#{digits}" if digits.present? && digits.delete('0-9').empty?
  end

  def write_page(contact_inbox, rows)
    contact_inbox.with_lock do
      conversation = history_conversation(contact_inbox)
      raise Waha::Client::Error, 'history_outbound_pending' if conversation.messages.pending_waha_outbound.exists?

      imported = rows.uniq { |row| row[:payload]['id'] }.reject { |row| @inbox.messages.with_waha_source_id(row[:payload]['id']).exists? }
      imported.each { |row| write_message(conversation, contact_inbox.contact, row) }
      { imported: imported.size, unavailable_media: imported.count { |row| row[:unavailable_media] } }
    end
  end

  def history_conversation(contact_inbox)
    conversation = contact_inbox.conversations.last || Conversation.create!(
      account: @inbox.account, inbox: @inbox, contact: contact_inbox.contact,
      contact_inbox: contact_inbox, status: :resolved, waiting_since: nil,
      agent_last_seen_at: Time.zone.at(@before), additional_attributes: { 'history_import' => true, 'waha_history_only' => true }
    )
    if !conversation.messages.incoming.without_waha_history.exists? &&
       (conversation.agent_last_seen_at.nil? || conversation.agent_last_seen_at.to_i < @before)
      # Advance only to the connection cutoff, preserving every newer live unread.
      conversation.update_columns(agent_last_seen_at: Time.zone.at(@before)) # rubocop:disable Rails/SkipsModelValidations
    end
    conversation
  end

  def write_message(conversation, contact, row)
    message = build_message(conversation, contact, row)
    if row[:file]
      message.attachments.new(
        account_id: @inbox.account_id, file_type: file_type(row[:mimetype]),
        file: { io: row[:file], filename: File.basename(URI.parse(row[:url]).path), content_type: row[:mimetype] }
      )
    end
    message.save!
  end

  def build_message(conversation, contact, row)
    payload = row[:payload]
    attributes = { 'history_import' => true, 'waha_history_import' => true, 'external_echo' => true, 'external_created_at' => payload['timestamp'] }
    attributes['is_history_media_placeholder'] = true if row[:unavailable_media]
    content = payload['body'].presence
    content ||= I18n.t('conversations.messages.whatsapp.unsupported_message') unless row[:file]
    conversation.messages.new(
      account_id: @inbox.account_id, inbox_id: @inbox.id, source_id: payload['id'],
      content: content, private: false, created_at: Time.zone.at(payload['timestamp']),
      message_type: payload['fromMe'] ? :outgoing : :incoming,
      status: payload['fromMe'] ? :delivered : :read,
      sender: payload['fromMe'] ? nil : contact, content_attributes: attributes
    )
  end
end
