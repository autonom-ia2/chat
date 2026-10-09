require 'rails_helper'

RSpec.describe 'Autonomia agent handoff targets', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom', instruction: 'Atenda.')
  end
  let(:headers) { administrator.create_new_auth_token }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def link_agent_to(inbox)
    mirror = AgentBot.create!(account: account, name: agent.name, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: mirror)
  end

  it 'returns members common to every linked inbox and teams from the current account' do
    first_inbox = create(:inbox, account: account)
    second_inbox = create(:inbox, account: account)
    common_member = create(:user, account: account, role: :agent, name: 'Comum')
    first_only = create(:user, account: account, role: :agent, name: 'Só primeira')
    create(:inbox_member, inbox: first_inbox, user: common_member)
    create(:inbox_member, inbox: first_inbox, user: first_only)
    create(:inbox_member, inbox: second_inbox, user: common_member)
    link_agent_to(first_inbox)
    link_agent_to(second_inbox)
    team = create(:team, account: account, name: 'Equipe da conta')
    foreign_team = create(:team, account: create(:account), name: 'Equipe estrangeira')

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/handoff_targets",
        headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('members')).to include(
      { 'id' => administrator.id, 'name' => administrator.name },
      { 'id' => common_member.id, 'name' => common_member.name }
    )
    expect(response.parsed_body.fetch('members')).not_to include(
      { 'id' => first_only.id, 'name' => first_only.name }
    )
    expect(response.parsed_body.fetch('teams')).to include('id' => team.id, 'name' => team.name)
    expect(response.parsed_body.fetch('teams')).not_to include('id' => foreign_team.id, 'name' => foreign_team.name)
  end
end
