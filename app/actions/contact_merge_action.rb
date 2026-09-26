class ContactMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_contact!, :mergee_contact!]

  # chat#713: da origem de recusa mais firme para a mais fraca, na mescla de dois contatos que recusaram.
  OPT_OUT_PRECEDENCE = %w[manual email_unsubscribe prospecting].freeze

  def perform
    # This case happens when an agent updates a contact email in dashboard,
    # while the contact also update his email via email collect box
    return @base_contact if base_contact.id == mergee_contact.id

    ActiveRecord::Base.transaction do
      validate_contacts
      merge_conversations
      merge_messages
      merge_contact_inboxes
      merge_contact_notes
      merge_calls
      merge_and_remove_mergee_contact
    end
    @base_contact
  end

  private

  def validate_contacts
    return if belongs_to_account?(@base_contact) && belongs_to_account?(@mergee_contact)

    raise StandardError, 'contact does not belong to the account'
  end

  def belongs_to_account?(contact)
    @account.id == contact.account_id
  end

  def merge_conversations
    Conversation.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_contact_notes
    Note.where(contact_id: @mergee_contact.id, account_id: @mergee_contact.account_id).update(contact_id: @base_contact.id)
  end

  def merge_messages
    Message.where(sender: @mergee_contact).update(sender: @base_contact)
  end

  def merge_contact_inboxes
    ContactInbox.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_calls
    # overridden in enterprise/app/actions/enterprise/contact_merge_action.rb
  end

  def merge_and_remove_mergee_contact
    mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
    base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
    mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank

    # attributes in base contact are given preference
    merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)
    @mergee_contact.reload
    merged_attributes = merged_attributes.merge(inherited_opt_out)

    @mergee_contact.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    @base_contact.update!(merged_attributes)
  end

  # chat#713: a recusa de mensagens ativas é da pessoa. Se só o contato absorvido tinha recusado, a recusa (data, origem
  # e autor) passa para o que fica. Se os dois recusaram, fica a origem mais firme (a manual, depois o descadastro de
  # e-mail, depois a da Prospecção, que o "Desfazer" do lead solta sozinho) e a data mais antiga. Assim a mescla não
  # apaga uma recusa manual atrás de uma da Prospecção.
  def inherited_opt_out
    return {} unless @mergee_contact.opted_out?
    return opt_out_attributes(@mergee_contact) unless @base_contact.opted_out?

    kept = opt_out_rank(@mergee_contact) < opt_out_rank(@base_contact) ? @mergee_contact : @base_contact
    opt_out_attributes(kept).merge('opted_out_at' => [@base_contact.opted_out_at, @mergee_contact.opted_out_at].min)
  end

  def opt_out_attributes(contact)
    contact.attributes.slice('opted_out_at', 'opt_out_source', 'opted_out_by_id')
  end

  def opt_out_rank(contact)
    OPT_OUT_PRECEDENCE.index(contact.opt_out_source) || OPT_OUT_PRECEDENCE.size
  end
end

ContactMergeAction.prepend_mod_with('ContactMergeAction')
