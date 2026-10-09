require 'rails_helper'

RSpec.describe 'Agentes typed list', type: :request do
  let(:account) { create(:account, locale: 'pt_BR', internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'returns safe typed states, omits internal metrics and excludes archived and foreign agents', :aggregate_failures do
    external = Autonomia::Agents::Agent.create!(account: account, name: 'External', agent_type: 'custom',
                                                status: :active, enabled: true, instruction: 'Hidden instruction', scaffold: 'Hidden scaffold')
    internal = Autonomia::Agents::Agent.create!(account: account, name: 'Team', agent_type: 'custom', actuation: :internal,
                                                status: :paused, enabled: false, instruction: 'Hidden internal instruction')
    draft = Autonomia::Agents::Agent.create!(account: account, name: 'Draft', agent_type: 'custom',
                                             config: { 'voice' => 'masculina', '_autonomia_agents_redesign' => { 'version' => 1 } })
    manual = Autonomia::Agents::Agent.create!(account: account, name: 'Manual', agent_type: 'custom', mode: :manual)
    archived = Autonomia::Agents::Agent.create!(account: account, name: 'Archived', agent_type: 'custom', deleted_at: Time.current)
    foreign = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Foreign', agent_type: 'custom')
    system = Autonomia::Agents::Agent.create!(account: account, name: 'System', agent_type: 'custom', config: { 'system_key' => 'guide' })

    get url, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('payload').index_by { |row| row.fetch('id') }
    states = rows.transform_values { |row| row.fetch('state').slice('code', 'continuation', 'retention_hours') }
    expect(states).to eq(
      external.id => { 'code' => 'E5', 'continuation' => 'open' },
      internal.id => { 'code' => 'E6', 'continuation' => 'open' },
      draft.id => { 'code' => 'E1', 'continuation' => 'tell', 'retention_hours' => 48 },
      manual.id => { 'code' => 'E2m', 'continuation' => 'manual', 'retention_hours' => nil }
    )
    expect(rows[external.id].fetch('stats')).to eq(
      'week' => { 'replies' => 0, 'handoffs' => 0 }, 'month' => { 'replies' => 0, 'handoffs' => 0 }
    )
    expect(rows[internal.id]).not_to have_key('stats')
    expect(rows[draft.id].fetch('voice')).to eq('masculina')
    expect(rows[manual.id].fetch('voice')).to eq('feminina')
    expect(rows.values).to all(include('channels' => [], 'copilot_available' => be_in([true, false])))
    expect(response.parsed_body).to include(
      'meta' => include('total_count' => 4),
      'payload' => all(satisfy { |row| !row.keys.intersect?(%w[instruction scaffold messages _autonomia_agents_redesign]) })
    )
    expect(response.body).not_to include('Hidden instruction', 'Hidden scaffold', foreign.name, archived.name, system.name)
  end

  it 'uses the documented inbox_id key for connected channels' do
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom')
    inbox = create(:inbox, account: account)
    bot = AgentBot.create!(account: account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(account: account, agent: agent, inbox: inbox, agent_bot: bot)

    get url, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').sole.fetch('channels')).to eq(
      [{ 'inbox_id' => inbox.id, 'name' => inbox.name, 'channel_type' => inbox.channel_type }]
    )
  end

  describe 'global copilot availability' do
    let(:availability_service) { instance_double(Autonomia::Agents::CopilotAvailability, call: availability_result) }
    let(:availability_result) do
      Struct.new(:available, :reasons, :can_choose_internal).new(available, reasons, can_choose_internal)
    end
    let(:available) { true }
    let(:reasons) { [] }
    let(:can_choose_internal) { true }

    before do
      allow(Autonomia::Agents::CopilotAvailability).to receive(:new).with(account: account)
        .and_return(availability_service)
    end

    it 'returns the account-level contract even when there are no agents' do
      expect(availability_service).to receive(:call).once

      get url, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('copilot_availability')).to eq(
        'available' => true, 'can_choose_internal' => true, 'reasons' => []
      )
    end

    it 'returns the unavailable reasons and disables internal choice' do
      allow(availability_result).to receive(:available).and_return(false)
      allow(availability_result).to receive(:can_choose_internal).and_return(false)
      allow(availability_result).to receive(:reasons).and_return(%i[crm crm_ai])

      get url, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('copilot_availability')).to eq(
        'available' => false, 'can_choose_internal' => false, 'reasons' => %w[crm crm_ai]
      )
    end
  end

  it 'uses the latest thread without serializing its messages and leaves threads without an agent out of the list' do
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Unfinished', agent_type: 'custom')
    older = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, messages: [], updated_at: 1.hour.ago)
    latest = Autonomia::Agents::BuildThread.create!(account: account, agent: agent,
                                                    messages: [{ role: 'user', content: 'Private synthetic reply' }])
    unlinked = Autonomia::Agents::BuildThread.create!(account: account, messages: [{ role: 'user', content: 'Unlinked reply' }])
    older.update!(updated_at: Time.current)

    get url, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').sole.fetch('state')).to include('code' => 'E2', 'continuation' => 'tell')
    expect(response.body).not_to include('Private synthetic reply', 'Unlinked reply', 'messages', 'build_token')
    expect(latest.reload.autonomia_agent_id).to eq(agent.id)
    expect(unlinked.reload.autonomia_agent_id).to be_nil
  end

  it 'keeps all GET queries constant from one to twenty agents with materials, avatars, tools and channels' do
    headers = administrator.create_new_auth_token
    first = seed_list_agent(0)
    get url, headers: headers
    one_queries = capture_selects { get url, headers: headers }

    rest = (1...20).map { |index| seed_list_agent(index) }
    Autonomia::Agents::BuildThread.create!(account: account, messages: [{ role: 'user', content: 'unlinked secret' }])
    get url, headers: headers
    twenty_queries = capture_selects { get url, headers: headers }

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('payload').index_by { |row| row.fetch('id') }
    state_by_index = { 1 => 'E1', 2 => 'E2', 3 => 'E2m', 4 => 'E5', 5 => 'E4' }
    expected_states = (0...20).map { |index| state_by_index.fetch(index, 'E3') }
    expect(rows.transform_values { |row| row.fetch('state').fetch('code') }).to eq(
      [first, *rest].map(&:id).zip(expected_states).to_h
    )
    expect(rows.values).to all(satisfy { |row| !row.keys.intersect?(%w[instruction scaffold messages]) })
    expect(rows.values).to all(satisfy { |row| row.fetch('channels').length == 1 && row['avatar_url'].present? })
    expect(response.body).not_to include('unlinked secret', 'private reply', 'private instruction')
    expect(one_queries.length).to be <= 20
    expect(twenty_queries.length).to eq(one_queries.length), twenty_queries.join("\n")
  end

  it 'projects twenty agents within twelve SELECTs including the latest thread and all digest inputs' do
    agents = (0...20).map { |index| seed_list_agent(index) }
    scope = Autonomia::Agents::Agent.kept.where(account: account)
    Autonomia::Agents::ListProjection.new(agents: scope, account: account, locale: 'pt_BR').call

    projection = nil
    selects = capture_selects do
      projection = Autonomia::Agents::ListProjection.new(agents: scope, account: account, locale: 'pt_BR').call
    end

    expect(selects.length).to be <= 12
    expect(projection.keys).to match_array(agents.map(&:id))
    expect(projection[agents[0].id].fetch(:state)).to include(code: 'E3')
    expect(projection[agents[2].id].fetch(:state)).to include(code: 'E2')
    expect(projection[agents[4].id].fetch(:state)).to include(code: 'E5')
    expect(projection[agents[5].id].fetch(:state)).to include(code: 'E4')
  end

  it 'keeps native availability and SELECT counts bounded for twenty draft agents' do
    with_modified_env INSURANCE_QUOTING_ENABLED: 'true' do
      native_tool = Autonomia::Agents::Tools::Native::InsuranceCapabilities
      Autonomia::Insurance::Config.enable_for!(account)
      Autonomia::Insurance::Connection.create!(account: account, status: 'ready', capabilities: {}, metadata: {})

      create_native_agent = lambda do |index|
        Autonomia::Agents::Agent.create!(account: account, name: "Native #{index}", agent_type: 'custom',
                                         instruction: 'private instruction',
                                         config: { 'native_tool_slugs' => [native_tool.slug] })
      end
      first = create_native_agent.call(0)
      scope = Autonomia::Agents::Agent.kept.where(account: account)
      expect(Autonomia::Insurance::Config.enabled?(account)).to be(true)
      expect(Autonomia::Agents::Tools::Registry.for_agent(first)).to eq([native_tool])

      one_selects = capture_selects do
        Autonomia::Agents::ListProjection.new(agents: scope, account: account, locale: 'pt_BR').call
      end

      rest = (1...20).map { |index| create_native_agent.call(index) }
      many_selects = capture_selects do
        Autonomia::Agents::ListProjection.new(agents: scope, account: account, locale: 'pt_BR').call
      end

      expect([first, *rest]).to all(be_persisted)
      expect(many_selects.length).to eq(one_selects.length)
      expect(many_selects.length).to be <= 12
    end
  end

  def seed_list_agent(index)
    attributes = { account: account, name: "Synthetic #{index}", agent_type: 'custom', instruction: 'private instruction' }
    attributes[:instruction] = nil if [1, 2, 3].include?(index)
    attributes[:mode] = :manual if index == 3
    attributes.merge!(agent_type: 'insurance_quote', status: :active, enabled: true) if index == 4
    agent = Autonomia::Agents::Agent.create!(attributes)
    agent.avatar.attach(fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
    seed_list_material(agent, index)
    unless index.zero? || index == 1
      Autonomia::Agents::BuildThread.create!(account: account, agent: agent, messages: [{ role: 'user', content: 'private reply' }])
    end
    seed_list_channel_and_tool(agent)
    seed_completed_test(agent) if index == 5
    agent
  end

  def seed_list_material(agent, index)
    source = Autonomia::Agents::Source.create!(account: account, agent: agent, source_type: 'txt',
                                               kind: index == 1 ? :media : :knowledge,
                                               status: index == 1 ? :pending : :ready, review_status: 'accepted')
    return if index == 1

    Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: agent, source: source,
                                              content: 'synthetic material', status: :ready, chunk_index: 0)
  end

  def seed_list_channel_and_tool(agent)
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Synthetic lookup', slug: 'synthetic_lookup',
                                    endpoint_url: 'https://example.com/lookup', enabled: true)
    inbox = create(:inbox, account: account)
    bot = AgentBot.create!(account: account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(account: account, agent: agent, inbox: inbox, agent_bot: bot)
  end

  def seed_completed_test(agent)
    actor = administrator.account_users.find_by!(account: account)
    digest = Autonomia::Agents::TestDigest.for_agent(agent: agent)
    session_id = SecureRandom.uuid
    Autonomia::Agents::AgentStateStore.start_pending!(agent: agent, session_id: session_id, actor: actor, actor_permission: 'autonomia_manage')
    Autonomia::Agents::AgentStateStore.complete!(
      agent: agent, session_id: session_id, actor: actor, actor_permission: 'autonomia_manage',
      tested_digest: digest.fetch(:tested_digest), tested_person_digest: digest.fetch(:person_digest),
      material_snapshot_digest: digest.fetch(:material_snapshot_digest), material_snapshot_state: digest.fetch(:material_snapshot_state)
    )
  end

  def capture_selects(&)
    selects = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s.strip
      selects << sql if sql.upcase.start_with?('SELECT', 'WITH')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    selects
  end
end
