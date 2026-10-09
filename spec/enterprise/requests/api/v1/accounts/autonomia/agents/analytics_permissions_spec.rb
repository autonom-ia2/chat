require 'rails_helper'

# BE-25 — custom-role conversation visibility is an Enterprise policy boundary.
RSpec.describe 'Autonomia agent analytics permissions (Enterprise)', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conversation.id, event_type: :replied)
  end

  it 'returns no conversations to an agent who can see Autonomia but has no conversation permission' do
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    viewer.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: viewer, inbox: inbox)

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
        params: { range: '7d', metric: 'handled' }, headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']).to include('count' => 0, 'has_hidden' => true)
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'limits the drilldown to conversations assigned to or involving a participating custom-role user' do
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account,
                                permissions: %w[autonomia_view conversation_participating_manage])
    viewer.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: viewer, inbox: inbox)

    assigned = create(:conversation, account: account, inbox: inbox, assignee: viewer)
    participating = create(:conversation, account: account, inbox: inbox,
                                          assignee: create(:user, account: account, role: :agent))
    create(:conversation_participant, account: account, conversation: participating, user: viewer)
    hidden = create(:conversation, account: account, inbox: inbox,
                                   assignee: create(:user, account: account, role: :agent))

    [assigned, participating, hidden].each do |conversation_record|
      Autonomia::Agents::AgentEvent.create!(agent: agent, account: account,
                                            conversation_id: conversation_record.id, event_type: :replied)
    end

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
        params: { range: '7d', metric: 'handled' }, headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    display_ids = response.parsed_body['payload'].map { |row| row.dig('conversation', 'display_id') }
    expect(display_ids).to contain_exactly(assigned.display_id, participating.display_id)
    expect(display_ids).not_to include(hidden.display_id, conversation.display_id)
  end

  it 'flags conversations in another inbox without exposing their identity' do
    # The shared setup creates a handled conversation for permission-only examples. It is
    # unrelated to this inbox comparison, so remove its event before defining the two cases.
    agent.events.where(conversation_id: conversation.id).delete_all

    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[autonomia_view conversation_manage])
    viewer.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: viewer, inbox: inbox)

    visible = create(:conversation, account: account, inbox: inbox)
    hidden_inbox = create(:inbox, account: account, name: 'Caixa fora do escopo')
    hidden_contact = create(:contact, account: account, name: 'Contato fora do escopo')
    hidden = create(:conversation, account: account, inbox: hidden_inbox, contact: hidden_contact)
    [visible, hidden].each do |conversation_record|
      Autonomia::Agents::AgentEvent.create!(agent: agent, account: account,
                                            conversation_id: conversation_record.id, event_type: :replied)
    end

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
        params: { range: '7d', metric: 'handled' }, headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['meta']).to include('count' => 1, 'has_hidden' => true)
    conversation_rows = body.fetch('payload').map { |row| row.fetch('conversation') }
    expect(conversation_rows.map { |row| row.fetch('display_id') }).to eq([visible.display_id])
    expect(conversation_rows.map { |row| row.fetch('display_id') }).not_to include(hidden.display_id)
    expect(conversation_rows.map { |row| row.fetch('inbox_id') }).not_to include(hidden_inbox.id)
    expect(conversation_rows.map { |row| row.fetch('contact_id') }).not_to include(hidden_contact.id)
    expect(response.body).not_to include('Caixa fora do escopo', 'Contato fora do escopo')
  end

  it 'keeps an agent from another account out of the drilldown route' do
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_agent = Autonomia::Agents::Agent.create!(
      account: other_account, name: 'Outro', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda.'
    )

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{foreign_agent.id}/analytics/conversations",
        params: { range: '7d', metric: 'handled' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
