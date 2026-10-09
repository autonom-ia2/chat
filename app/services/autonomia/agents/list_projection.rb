class Autonomia::Agents::ListProjection
  attr_reader :agents, :copilot_availability

  def initialize(agents:, account:, locale:)
    @scope = agents
    @account = account
    @locale = locale
  end

  def call
    @agents = @scope.with_attached_avatar.includes(agent_inboxes: :inbox).to_a
    @copilot_result = Autonomia::Agents::CopilotAvailability.new(account: @account).call
    @copilot_availability = {
      available: @copilot_result.available,
      can_choose_internal: @copilot_result.can_choose_internal,
      reasons: Array(@copilot_result.reasons).map(&:to_s)
    }
    return {} if @agents.empty?

    load_inputs
    @agents.to_h { |agent| [agent.id, row_for(agent)] }
  end

  private

  def load_inputs
    ids = @agents.map(&:id)
    account_ids = @agents.map(&:account_id).uniq
    @draft_agents = @agents.select(&:draft?)
    preload_draft_accounts
    @threads = latest_threads(ids, account_ids)
    sources = Autonomia::Agents::Source.where(autonomia_agent_id: ids, account_id: account_ids, kind: :knowledge).to_a
    @versions = entry_versions(ids, account_ids, sources.map(&:id))
    @sources = sources.group_by(&:autonomia_agent_id)
    @tools = tools_by_agent(account_ids)
    @connection_readiness = connection_readiness
    @native_tools = native_tools_by_agent
    @stats = Autonomia::Agents::ListStats.new(agents: @agents.reject(&:actuation_internal?)).call
  end

  def preload_draft_accounts
    return if @draft_agents.empty?

    ActiveRecord::Associations::Preloader.new(
      records: @draft_agents, associations: :account, available_records: [@account]
    ).call
  end

  def connection_readiness
    return {} unless @draft_agents.any? { |agent| Array(agent.ferramentas_nativas).any? }

    Autonomia::Insurance::Connection.preload_for_accounts(@draft_agents.map(&:account_id))
  end

  def tools_by_agent(account_ids)
    draft_ids = @draft_agents.map(&:id)
    tool_scope = Autonomia::Agents::Tool.where(autonomia_agent_id: draft_ids, account_id: account_ids)
    tool_scope.select(:id, :autonomia_agent_id, :slug, :enabled, :updated_at).group_by(&:autonomia_agent_id)
  end

  def native_tools_by_agent
    Autonomia::Agents::Tools::Registry.for_agents(@draft_agents, readiness: @connection_readiness)
  end

  def row_for(agent)
    material = Autonomia::Agents::MaterialProjection.new(
      agent: agent, sources: @sources.fetch(agent.id, []), entry_versions: @versions
    ).call
    row = { state: resolved_state(agent, @threads.fetch(agent.id, {}), material, @tools.fetch(agent.id, [])),
            channels: channels_for(agent), copilot_available: @copilot_result.available }
    row[:stats] = @stats.fetch(agent.id) unless agent.actuation_internal?
    row
  end

  def latest_threads(ids, account_ids)
    selection = <<~SQL.squish
      DISTINCT ON (autonomia_agent_id) autonomia_agent_id,
      state->>'needs_more_info' = 'true' AS needs_more_info,
      state->>'with_knowledge' = 'true' AS with_knowledge,
      state->>'no_materials_declared' = 'true' AS no_materials_declared,
      EXISTS (SELECT 1 FROM jsonb_array_elements(messages) AS entry WHERE entry->>'role' = 'user') AS user_response
    SQL
    thread_scope = Autonomia::Agents::BuildThread.where(autonomia_agent_id: ids, account_id: account_ids)
    thread_scope.order(:autonomia_agent_id, id: :desc)
                .pluck(Arel.sql(selection))
                .to_h do |agent_id, needs_more_info, with_knowledge, no_materials_declared, user_response|
      [agent_id, { needs_more_info: needs_more_info, with_knowledge: with_knowledge,
                   no_materials_declared: no_materials_declared, user_response: user_response }]
    end
  end

  def entry_versions(ids, account_ids, source_ids)
    entry_scope = Autonomia::Agents::KnowledgeEntry.where(
      autonomia_agent_id: ids, account_id: account_ids, source_id: source_ids, status: :ready
    )
    entries = entry_scope.group(:source_id).pluck(:source_id, Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)'))
    entries.to_h do |source_id, count, updated_at|
      [source_id, { ready_count: count, latest_updated_at: updated_at }]
    end
  end

  def resolved_state(agent, thread, material, tools)
    private_state = Autonomia::Agents::AgentStateStore.read(agent: agent)
    test = private_state.fetch(:test).to_h.merge(test_invalidated_by: private_state[:test_invalidated_by])
    digest = current_digest(agent, material, tools)
    state = Autonomia::Agents::AgentStateResolver.resolve(
      agent: state_input(agent, material),
      thread: thread, test: test, current_digest: digest[:tested_digest], current_person_digest: digest[:person_digest],
      current_material_digest: digest[:material_snapshot_digest], session_id: test[:session_id],
      state_version: private_state[:version], retention_hours: agent.manual? ? nil : Autonomia::Agents::Config.draft_reap_hours
    )
    state.except(:text, :invalidated_by).merge(
      label: I18n.t("autonomia.agents.redesign.states.#{state.fetch(:code)}", locale: @locale),
      test_invalidated_by: state[:invalidated_by]
    )
  end

  def current_digest(agent, material, tools)
    return {} unless agent.draft?

    Autonomia::Agents::TestDigest.for_agent(
      agent: agent, material_projection: material, tools: tools,
      native_tools: @native_tools.fetch(agent.id, [])
    )
  end

  def state_input(agent, material)
    { archived: agent.deleted?, status: agent.status, enabled: agent.enabled?, mode: agent.mode,
      actuation: agent.actuation, instruction_present: agent.instrucao_mantida? || agent.instruction.present?,
      has_material: material.decisions.any? }
  end

  def channels_for(agent)
    agent.agent_inboxes.select { |link| link.deleted_at.nil? && link.account_id == agent.account_id }.map do |link|
      inbox = link.inbox
      { inbox_id: inbox.id, name: inbox.name, channel_type: inbox.channel_type }
    end
  end
end
