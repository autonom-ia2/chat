class Mcp::Tools::ListAgents < Mcp::Tools::Base
  tool_name 'list_agents'
  description 'List the people who work in the account (agents and administrators) and whether they are online. ' \
              'Use the agent id in assign_conversation.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(properties: {})

  def self.perform
    account_users = Current.account.account_users.human.includes(:user).order(:id)

    respond(agents: account_users.map do |account_user|
      { id: account_user.user_id, name: account_user.user.name, email: account_user.user.email, role: account_user.role,
        availability: account_user.availability_status }
    end)
  end
end
