require 'rails_helper'

# BE-03/BE-04 — publicação da jornada nova. O endpoint é a porta pública do
# Publisher: toda mudança de agente e de vínculo precisa terminar inteira ou
# não deixar nenhum efeito parcial.
RSpec.describe 'Autonomia agent publisher', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:other_account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:account_user) { administrator.account_users.find_by!(account: account) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before { stub_copilot(available: true) }

  def create_agent(owner, attrs = {})
    Autonomia::Agents::Agent.create!(
      {
        account: owner,
        name: 'Clara',
        agent_type: 'custom',
        mode: :guided,
        status: :draft,
        enabled: false,
        actuation: :external,
        instruction: 'Atenda os clientes com clareza.'
      }.merge(attrs)
    )
  end

  def mark_valid_test(agent)
    material = Autonomia::Agents::MaterialProjection.new(agent: agent).call
    digest = Autonomia::Agents::TestDigest.for_agent(agent: agent, material_projection: material, tools: [])
    session_id = "publish-test-#{SecureRandom.hex(8)}"

    start_test_session(agent, session_id)
    complete_test_session(agent, session_id, digest)
  end

  def start_test_session(agent, session_id)
    Autonomia::Agents::AgentStateStore.start_pending!(
      agent: agent, session_id: session_id, actor: account_user, actor_permission: 'autonomia_manage'
    )
  end

  def complete_test_session(agent, session_id, digest)
    Autonomia::Agents::AgentStateStore.complete!(
      agent: agent,
      session_id: session_id,
      actor: account_user,
      actor_permission: 'autonomia_manage',
      result: { 'reply' => 'Resposta concluída' },
      result_real_ai_deferred: true,
      valid_for_state: true,
      tested_digest: digest.fetch(:tested_digest),
      tested_person_digest: digest.fetch(:person_digest),
      material_snapshot_digest: digest.fetch(:material_snapshot_digest),
      material_snapshot_state: digest.fetch(:material_snapshot_state),
      skipped_tools: []
    )
  end

  def publish(agent, params: {})
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/publish",
         params: params, headers: administrator.create_new_auth_token, as: :json
  end

  def stub_copilot(available:)
    result = Struct.new(:available, :reasons, :can_choose_internal).new(
      available, available ? [] : [:crm], available
    )
    service = instance_double(Autonomia::Agents::CopilotAvailability, call: result)
    allow(Autonomia::Agents::CopilotAvailability).to receive(:new).and_return(service)
  end

  it 'publishes an externally acting agent atomically after a valid test' do
    agent = create_agent(account, config: { 'response_window' => 'always' })
    inbox = create(:inbox, account: account, name: 'Caixa principal')
    mark_valid_test(agent)

    publish(agent, params: { inbox_id: inbox.id, agent: { config: { response_window: 'business_hours' } } })

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('state', 'writes_external')
    expect(agent.reload).to have_attributes(status: 'active', enabled: true)
    expect(agent.response_window).to eq('business_hours')
    link = Autonomia::Agents::AgentInbox.kept.find_by!(agent: agent, inbox: inbox)
    expect(link.agent_bot).to be_present
    expect(AgentBotInbox.find_by!(inbox: inbox, agent_bot: link.agent_bot)).to be_active
  end

  it 'publishes an externally acting agent to multiple inboxes in one transaction' do
    agent = create_agent(account)
    inboxes = create_list(:inbox, 2, account: account)
    mark_valid_test(agent)

    publish(agent, params: { inbox_ids: inboxes.map(&:id) })

    expect(response).to have_http_status(:success)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent).pluck(:inbox_id)).to match_array(inboxes.map(&:id))
    expect(AgentBotInbox.where(inbox_id: inboxes.map(&:id)).count).to eq(2)
    expect(agent.reload).to have_attributes(status: 'active', enabled: true)
  end

  it 'publishes an internal agent without accepting an inbox' do
    agent = create_agent(account, actuation: :internal)
    mark_valid_test(agent)

    publish(agent)

    expect(response).to have_http_status(:success)
    expect(agent.reload).to have_attributes(status: 'active', enabled: true)
    expect(agent.agent_inboxes.kept).to be_empty
  end

  it 'rejects an internal agent when an inbox is supplied' do
    agent = create_agent(account, actuation: :internal)
    inbox = create(:inbox, account: account)
    mark_valid_test(agent)

    publish(agent, params: { inbox_id: inbox.id })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('agent_internal_not_connectable')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'rejects an internal agent when the team copilot is unavailable' do
    agent = create_agent(account, actuation: :internal)
    mark_valid_test(agent)
    stub_copilot(available: false)

    publish(agent)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('copilot_unavailable')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'requires an existing inbox when publishing an external agent' do
    agent = create_agent(account)
    mark_valid_test(agent)

    publish(agent)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_required')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'rejects missing instruction before checking the test' do
    agent = create_agent(account, instruction: nil)

    publish(agent)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('missing_instruction')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
  end

  it 'rejects an instruction that has not received a valid test' do
    agent = create_agent(account)

    publish(agent)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('missing_test')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
  end

  it 'rejects name and greeting in the publish body before mutating the agent' do
    agent = create_agent(account, name: 'Nome antigo', greeting: 'Saudação antiga')
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('name', 'greeting', 'status', 'enabled', 'config')

    publish(agent, params: { agent: { name: 'Nome novo', greeting: 'Saudação nova' } })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('publish_field_not_allowed')
    expect(agent.reload.attributes.slice('name', 'greeting', 'status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'scopes the agent lookup to the current account' do
    foreign_agent = create_agent(other_account, name: 'Agente de outra conta')

    publish(foreign_agent)

    expect(response).to have_http_status(:not_found)
    expect(foreign_agent.reload).to have_attributes(status: 'draft', enabled: false)
  end

  it 'rejects an inbox from another account without changing the agent' do
    agent = create_agent(account, config: { 'response_window' => 'always' })
    foreign_inbox = create(:inbox, account: other_account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_id: foreign_inbox.id })

    expect(response).to have_http_status(:not_found)
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'rejects a multi-inbox selection containing another account without changing the agent' do
    agent = create_agent(account)
    local_inbox = create(:inbox, account: account)
    foreign_inbox = create(:inbox, account: other_account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_ids: [local_inbox.id, foreign_inbox.id] })

    expect(response).to have_http_status(:not_found)
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
  end

  it 'rolls back activation and config when the inbox is already connected' do
    first_agent = create_agent(account, name: 'Primeiro', status: :active, enabled: true)
    inbox = create(:inbox, account: account)
    first_link = Autonomia::Agents::Operate::InboxConnector.new(agent: first_agent, inbox: inbox).perform(connect: true)
    expect(first_link).to be_success

    second_agent = create_agent(account, name: 'Segundo', config: { 'response_window' => 'business_hours' })
    mark_valid_test(second_agent)
    before = second_agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(second_agent, params: { inbox_id: inbox.id, agent: { config: { response_window: 'business_hours' } } })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_already_connected')
    expect(second_agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.find_by!(inbox: inbox).agent).to eq(first_agent)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: second_agent)).to be_empty
  end

  it 'rolls back every inbox when one inbox in a multi-inbox publish is occupied' do
    first_agent = create_agent(account, name: 'Primeiro', status: :active, enabled: true)
    occupied_inbox = create(:inbox, account: account)
    free_inbox = create(:inbox, account: account)
    connected = Autonomia::Agents::Operate::InboxConnector.new(
      agent: first_agent, inbox: occupied_inbox
    ).perform(connect: true)
    expect(connected).to be_success

    second_agent = create_agent(account, config: { 'response_window' => 'business_hours' })
    mark_valid_test(second_agent)
    before = second_agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(second_agent, params: { inbox_ids: [free_inbox.id, occupied_inbox.id] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_already_connected')
    expect(second_agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: second_agent)).to be_empty
    expect(Autonomia::Agents::AgentInbox.kept.find_by!(inbox: occupied_inbox).agent).to eq(first_agent)
    expect(Autonomia::Agents::AgentInbox.kept.find_by(inbox: free_inbox)).to be_nil
  end

  it 'rolls back every inbox when one inbox has a webhook bot' do
    agent = create_agent(account)
    webhook_inbox = create(:inbox, account: account)
    free_inbox = create(:inbox, account: account)
    webhook_bot = AgentBot.create!(account: account, name: 'Gabriela', outgoing_url: 'https://example.com/hook')
    AgentBotInbox.create!(inbox: webhook_inbox, agent_bot: webhook_bot, account: account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_ids: [free_inbox.id, webhook_inbox.id] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_has_webhook_bot')
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
    expect(AgentBotInbox.find_by(inbox: free_inbox)).to be_nil
    expect(AgentBotInbox.where(inbox: webhook_inbox).pluck(:agent_bot_id)).to eq([webhook_bot.id])
  end

  it 'rolls back every mirror when the second mirror creation fails' do
    agent = create_agent(account)
    inboxes = create_list(:inbox, 2, account: account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')
    calls = 0
    allow(AgentBotInbox).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
      calls += 1
      raise ActiveRecord::RecordInvalid, AgentBotInbox.new if calls == 2

      original.call(*args, **kwargs)
    end

    expect do
      Autonomia::Agents::Publisher.new(agent: agent, inboxes: inboxes).perform
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(calls).to eq(2)
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
    expect(Autonomia::Agents::AgentInbox.kept.where(agent: agent)).to be_empty
    expect(AgentBotInbox.where(inbox: inboxes)).to be_empty
    expect(AgentBot.where(account: account, outgoing_url: nil)).to be_empty
  end

  it 'rejects an internal agent when a non-empty inbox list is supplied' do
    agent = create_agent(account, actuation: :internal)
    inbox = create(:inbox, account: account)
    mark_valid_test(agent)

    publish(agent, params: { inbox_ids: [inbox.id] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('agent_internal_not_connectable')
    expect(agent.reload).to have_attributes(status: 'draft', enabled: false)
    expect(agent.agent_inboxes.kept).to be_empty
  end

  it 'rejects a multi-inbox selection with a non-integer id' do
    agent = create_agent(account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_ids: [1, '2'] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_selection_invalid')
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
  end

  it 'rejects duplicate inbox ids before changing the agent' do
    agent = create_agent(account)
    inbox = create(:inbox, account: account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_ids: [inbox.id, inbox.id] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_selection_invalid')
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
  end

  it 'rejects singular and plural inbox selections together' do
    agent = create_agent(account)
    inbox = create(:inbox, account: account)
    mark_valid_test(agent)
    before = agent.reload.attributes.slice('status', 'enabled', 'config')

    publish(agent, params: { inbox_id: inbox.id, inbox_ids: [] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('inbox_selection_conflict')
    expect(agent.reload.attributes.slice('status', 'enabled', 'config')).to eq(before)
  end

  it 'keeps internal agents without inboxes when an empty list is explicit' do
    agent = create_agent(account, actuation: :internal)
    mark_valid_test(agent)

    publish(agent, params: { inbox_ids: [] })

    expect(response).to have_http_status(:success)
    expect(agent.reload).to have_attributes(status: 'active', enabled: true)
    expect(agent.agent_inboxes.kept).to be_empty
  end
end
