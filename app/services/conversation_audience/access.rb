# Who may run a search by conversation (#2277): the gate of the controller (campaign_manage AND conversation_view, or
# an administrator), checked again by each job. A person who lost the role or left the account while the search waited
# in line stops spending the account's AI key.
module ConversationAudience::Access
  PERMISSIONS = %w[campaign_manage conversation_view].freeze
  ERROR = 'no_access'.freeze

  module_function

  def allowed?(search)
    account_user = search.user_id && AccountUser.find_by(account_id: search.account_id, user_id: search.user_id)
    account_user.present? && PERMISSIONS.all? { |key| account_user.permission_granted?(key) }
  end
end
