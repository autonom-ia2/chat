class Mcp::Tools::ListTeams < Mcp::Tools::Base
  tool_name 'list_teams'
  description 'List the teams of the account with their members. Use the team id in assign_conversation.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(properties: {})

  def self.perform
    teams = Current.account.teams.includes(:members).order(:name)

    respond(teams: teams.map { |team| { id: team.id, name: team.name, description: team.description, members: team.members.map(&:name) } })
  end
end
