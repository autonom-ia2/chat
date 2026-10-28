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

  # An audience built from the conversations takes its columns from the contacts, not from a file someone uploaded:
  # only who reads contacts sees their values (access review of #2303, Funções personalizadas, 28/10).
  def hides_contact_data?(campaign_import, account_user)
    campaign_import.options.to_h['source'] == SOURCE && !reads_contacts?(account_user)
  end
end
