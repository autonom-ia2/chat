# #990: ContactMergeAction tuned for the bulk ninth-digit merge (Contacts::NinthDigitDuplicateMerger).
class Contacts::NinthDigitMergeAction < ContactMergeAction
  private

  # One UPDATE instead of one save per message: no MESSAGE_UPDATED event / webhook burst per moved message.
  # update_all also skips Message#reindex_for_search. The app has no reindex job; with advanced search on, the moved
  # messages keep the old sender id in the search index until they are next saved (search by sender is not used).
  def merge_messages
    Message.where(sender_type: 'Contact', sender_id: @mergee_contact.id)
           .update_all(sender_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Moves again right before the destroy: a conversation, message or note that reached the mergee after the first
  # pass is carried over instead of being deleted with it (destroy_async).
  def merge_and_remove_mergee_contact
    merge_conversations
    merge_messages
    merge_contact_inboxes
    merge_contact_notes
    super
  end
end
