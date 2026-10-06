# This Builder will create a contact and contact inbox with specified attributes.
# If an existing identified contact exisits, it will be returned.
# for contact inbox logic it uses the contact inbox builder

class ContactInboxWithContactBuilder
  pattr_initialize [:inbox!, :contact_attributes!, :source_id, :hmac_verified]

  def perform
    if waha_history_connection? && inbox.channel.additional_attributes.dig('waha_history_import', 'status').in?(%w[waiting_connection running])
      return account.with_lock { find_or_create_contact_and_contact_inbox }
    end

    find_or_create_contact_and_contact_inbox
  # in case of race conditions where contact is created by another thread
  # we will try to find the contact and create a contact inbox
  rescue ActiveRecord::RecordNotUnique
    find_or_create_contact_and_contact_inbox
  end

  def find_or_create_contact_and_contact_inbox
    @contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) if source_id.present?
    return @contact_inbox if @contact_inbox

    ActiveRecord::Base.transaction(requires_new: true) do
      build_contact_with_contact_inbox
    end
    update_contact_avatar(@contact) unless @contact.avatar.attached?
    @contact_inbox
  end

  private

  def build_contact_with_contact_inbox
    @contact = find_contact || create_contact
    existing = inbox.contact_inboxes.find_by(contact_id: @contact.id) if waha_history_connection?
    @contact_inbox = existing || create_contact_inbox
  end

  def account
    @account ||= inbox.account
  end

  def create_contact_inbox
    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: @source_id,
      hmac_verified: hmac_verified
    ).perform
  end

  def update_contact_avatar(contact)
    ::Avatar::AvatarFromUrlJob.perform_later(contact, contact_attributes[:avatar_url]) if contact_attributes[:avatar_url]
  end

  def create_contact
    account.contacts.create!(
      name: contact_name,
      phone_number: contact_attributes[:phone_number],
      email: contact_attributes[:email],
      identifier: contact_attributes[:identifier],
      additional_attributes: contact_attributes[:additional_attributes],
      custom_attributes: contact_attributes[:custom_attributes]
    )
  end

  def contact_name
    name = contact_attributes[:name] || ::Haikunator.haikunate(1000)
    name.truncate(ApplicationRecord::MAX_STRING_COLUMN_LENGTH, omission: '')
  end

  def find_contact
    contact = find_waha_contact
    contact ||= find_contact_by_identifier(contact_attributes[:identifier])
    contact ||= find_contact_by_email(contact_attributes[:email])
    contact ||= find_contact_by_phone_numbers
    contact ||= find_contact_by_instagram_source_id(source_id) if instagram_channel?

    contact
  end

  # Native WAHA searches before POSTing a contact. Serialize that POST with history
  # and reuse its contact-inbox so a concurrent live event cannot create a second thread.
  def waha_history_connection?
    inbox.channel_type == 'Channel::Api' && inbox.channel.additional_attributes['provider'] == 'waha' &&
      inbox.channel.additional_attributes['waha_history_import'].present?
  end

  def find_waha_contact
    return unless waha_history_connection?

    attributes = contact_attributes[:custom_attributes].to_h.stringify_keys
    ids = attributes.values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid', 'waha_whatsapp_lid').compact_blank.uniq
    return if ids.empty?

    account.contacts.joins(:contact_inboxes).where(contact_inboxes: { inbox_id: inbox.id }).where(
      "contacts.identifier IN (:ids) OR contacts.custom_attributes ->> 'waha_whatsapp_chat_id' IN (:ids) OR " \
      "contacts.custom_attributes ->> 'waha_whatsapp_jid' IN (:ids) OR contacts.custom_attributes ->> 'waha_whatsapp_lid' IN (:ids)",
      ids: ids
    ).first
  end

  def instagram_channel?
    inbox.channel_type == 'Channel::Instagram'
  end

  # There might be existing contact_inboxes created through Channel::FacebookPage
  # with the same Instagram source_id. New Instagram interactions should create fresh contact_inboxes
  # while still reusing contacts if found in Facebook channels so that we can create
  # new conversations with the same contact.
  def find_contact_by_instagram_source_id(instagram_id)
    return if instagram_id.blank?

    existing_contact_inbox = ContactInbox.joins(:inbox)
                                         .where(source_id: instagram_id)
                                         .where(
                                           'inboxes.channel_type = ? AND inboxes.account_id = ?',
                                           'Channel::FacebookPage',
                                           account.id
                                         ).first

    existing_contact_inbox&.contact
  end

  def find_contact_by_identifier(identifier)
    return if identifier.blank?

    account.contacts.find_by(identifier: identifier)
  end

  def find_contact_by_email(email)
    return if email.blank?

    account.contacts.from_email(email)
  end

  def find_contact_by_phone_numbers
    phone_numbers = [contact_attributes[:phone_number], *Array(contact_attributes[:phone_number_candidates])].compact_blank.uniq
    if waha_history_connection? && contact_attributes[:phone_number].present?
      digits = contact_attributes[:phone_number].delete_prefix('+')
      alternatives = Whatsapp::PhoneNumberNormalizationService.new(inbox).phone_number_candidates(digits)
      phone_numbers.concat(alternatives.map { |number| "+#{number}" }).uniq!
    end

    phone_numbers.each do |phone_number|
      contact = account.contacts.find_by(phone_number: phone_number)
      return contact if contact
    end

    nil
  end
end
