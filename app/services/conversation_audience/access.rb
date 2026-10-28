# Who may run a search by conversation (#2277): the gate of the controller (campaign_manage AND conversation_view, or
# an administrator), checked again by each job. A person who lost the role or left the account while the search waited
# in line stops spending the account's AI key.
module ConversationAudience::Access
  PERMISSIONS = %w[campaign_manage conversation_view].freeze
  ERROR = 'no_access'.freeze
  # The contact's own data (company, city, custom attributes) is contact reading; contact_manage implies it.
  CONTACTS = 'contact_view'.freeze
  # Where a saved audience says it came from the conversations (ConversationAudience::Save).
  SOURCE = 'conversations'.freeze

  module_function

  def allowed?(search)
    account_user = search.user_id && AccountUser.find_by(account_id: search.account_id, user_id: search.user_id)
    account_user.present? && PERMISSIONS.all? { |key| account_user.permission_granted?(key) }
  end

  def reads_contacts?(account_user)
    account_user.present? && account_user.permission_granted?(CONTACTS)
  end

  def from_conversations?(campaign_import)
    campaign_import.options.to_h['source'] == SOURCE
  end

  # Who of an audience built from the conversations the viewer may see by name: the people whose conversation the
  # viewer can open (the name plus the audience's name tell what was said there; access review of #2303). An audience
  # without its search gives nobody. The count and the send are the audience's reach and stay whole.
  def visible_contact_ids(campaign_import, user)
    search_id = campaign_import.options.to_h['conversation_audience_search_id']
    return Set.new if search_id.blank? || user.nil?

    people = ConversationAudiencePerson.where(search_id: search_id)
    visible = ConversationAudience::Conversations.visible_ids(campaign_import.account, user, people.pluck(:conversation_id))
    people.where(conversation_id: visible.to_a).pluck(:contact_id).to_set
  end

  # An audience built from the conversations takes its columns from the contacts, not from a file someone uploaded:
  # only who reads contacts sees their values (access review of #2303, Funções personalizadas, 28/10).
  def hides_contact_data?(campaign_import, account_user)
    from_conversations?(campaign_import) && !reads_contacts?(account_user)
  end
end
