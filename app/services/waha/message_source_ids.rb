class Waha::MessageSourceIds
  IdentityConflict = Class.new(StandardError)
  LOCK_NAMESPACE = 5_551 # WAHA source-ID ownership, keyed by inbox.

  def initialize(message:, source_ids:)
    @message = message
    @source_ids = source_ids
  end

  def perform
    ActiveRecord::Base.transaction do
      lock_inbox_source_ids!
      @message.conversation.contact_inbox.with_lock do
        @message.with_lock { apply_identity! }
      end
    end
  end

  private

  def apply_identity!
    ensure_identity_available!(@message)
    return @message if identity_already_applied?(@message)

    @message.update!(source_id: @source_ids.first, additional_attributes: additional_attributes_with_source_ids(@message))
    @message
  end

  def lock_inbox_source_ids!
    inbox_id = @message.inbox_id.to_i
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{inbox_id})"
    )
  end

  def ensure_identity_available!(message)
    raise IdentityConflict, 'waha_message_identity_conflict' if current_identity_conflicts?(message)
    return unless source_ids_linked_to_another_message?(message)

    raise IdentityConflict, 'waha_message_identity_conflict'
  end

  def current_identity_conflicts?(message)
    attributes = message.additional_attributes.to_h
    source_ids_present = attributes.key?('waha_source_ids')
    (source_ids_present && attributes['waha_source_ids'] != @source_ids) ||
      (!message.source_id.nil? && message.source_id != @source_ids.first)
  end

  def source_ids_linked_to_another_message?(message)
    @source_ids.any? do |source_id|
      Message.with_waha_source_id(source_id)
             .where(inbox_id: message.inbox_id)
             .where.not(id: message.id)
             .exists?
    end
  end

  def identity_already_applied?(message)
    attributes = message.additional_attributes.to_h
    message.source_id == @source_ids.first &&
      attributes.key?('waha_source_ids') && attributes['waha_source_ids'] == @source_ids
  end

  def additional_attributes_with_source_ids(message)
    message.additional_attributes.to_h.merge('waha_source_ids' => @source_ids)
  end
end
