# The accounts one connection covers (#3106). It needs no account itself, so it reads no account_id.
class Mcp::Tools::ListAccounts < Mcp::Tools::Base
  tool_name 'list_accounts'
  description 'List the accounts the user administers, marking the one the other tools use by default. ' \
              'To act on another account, pass its id as account_id to the other tools. Pick the account by the name ' \
              'the user mentions, and ask which one when more than one matches.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)

  def self.call(server_context:, **)
    return insufficient_scope_response(server_context[:base_url]) unless server_context[:scopes].include?(required_scope)

    default_id = server_context[:default_account_id]
    accounts = account_access(server_context).account_users.map do |account_user|
      { id: account_user.account_id, name: account_user.account.name, default: account_user.account_id == default_id }
    end
    respond(accounts: accounts)
  end
end
