require 'rails_helper'

RSpec.describe 'Autonomia agent public config contract', type: :request do
  operational_keys = %w[
    voice_reply voice_instructions humanize_delivery operate_media operate_reactions
    test_allowlist_phones silence_tokens native_tool_slugs debounce_seconds async_tools
    async_poll_intervals async_deadline_seconds
  ].freeze

  protected_keys = %w[
    topic_map knowledge_confidence knowledge_summary knowledge_refresh_token
    with_knowledge builder_active_thread_id
  ].freeze

  forbidden_keys = (protected_keys + %w[system_key guide_kb_version temperature] + operational_keys + [
    Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA
  ]).freeze

  forbidden_values = {
    'topic_map' => [{ 'topic' => 'suporte' }],
    'test_allowlist_phones' => ['+5511999999999'],
    'silence_tokens' => ['custom_silence'],
    'native_tool_slugs' => [Autonomia::Agents::Tools::Registry.slugs.first],
    'async_poll_intervals' => [3, 8],
    'debounce_seconds' => 10,
    'async_deadline_seconds' => 120,
    'with_knowledge' => false,
    'system_key' => false,
    'builder_active_thread_id' => false
  }.freeze

  let!(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Agente público',
      agent_type: 'custom',
      instruction: 'Atenda com clareza.',
      config: { 'handoff_strategy' => 'none', 'existing_setting' => 'preserve' }
    )
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def patch_config(config, account_id: account.id, agent_id: agent.id, request_headers: headers)
    patch "/api/v1/accounts/#{account_id}/autonomia/agents/#{agent_id}",
          params: { agent: { config: config } }, headers: request_headers, as: :json
  end

  def post_agent(config)
    post "/api/v1/accounts/#{account.id}/autonomia/agents",
         params: { agent: { name: 'Novo agente', agent_type: 'custom', config: config } },
         headers: headers, as: :json
  end

  it 'merges only the closed public list and preserves the rest of the config' do
    patch_config({
                   'handoff_strategy' => 'none',
                   'handoff_target_type' => 'member',
                   'handoff_target_id' => 42,
                   'confidence_threshold' => 0.6,
                   'audience' => nil,
                   'audience_unknown_contact' => 'respond',
                   'response_window' => 'always',
                   'faq_suggestions' => true
                 })

    expect(response).to have_http_status(:success)
    expect(agent.reload.config).to include(
      'handoff_strategy' => 'none',
      'handoff_target_type' => 'member',
      'handoff_target_id' => 42,
      'confidence_threshold' => 0.6,
      'audience_unknown_contact' => 'respond',
      'audience' => nil,
      'response_window' => 'always',
      'faq_suggestions' => true,
      'existing_setting' => 'preserve'
    )
  end

  forbidden_keys.each do |key|
    it "rejects public writes to #{key} before sanitization" do
      before_config = agent.reload.config

      patch_config({ key => forbidden_values.fetch(key, true) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => key)
      expect(agent.reload.config).to eq(before_config)
    end
  end

  it 'rejects a mixed allowed and operational payload atomically' do
    before_config = agent.reload.config

    patch_config({ 'handoff_strategy' => 'none', 'voice_reply' => false })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'voice_reply')
    expect(agent.reload.config).to eq(before_config)
  end

  it 'preserves an audited operational write committed after the public request loaded its agent' do
    target_id = agent.id
    operation_actor = create(:super_admin)
    controller_class = Api::V1::Accounts::Autonomia::AgentsController
    controller = controller_class.new
    allow(controller_class).to receive(:new).and_return(controller)
    allow(controller).to receive(:fetch_agent).and_wrap_original do |original|
      original.call
      Autonomia::Agents::OperationConfig.new(
        agent: Autonomia::Agents::Agent.find(target_id),
        actor: operation_actor,
        operation_config: { 'voice_reply' => true }
      ).perform!
    end

    patch_config({ 'confidence_threshold' => 0.8 })

    expect(response).to have_http_status(:success)
    expect(agent.reload.config).to include('voice_reply' => true, 'confidence_threshold' => 0.8, 'existing_setting' => 'preserve')
    audit = Audited.audit_class.where(auditable: agent, action: 'update').sole
    expect(audit.audited_changes.fetch('operation_config').fetch('voice_reply')).to eq('old' => nil, 'new' => true)
  end

  it 'uses the same closed contract on create and does not create a partially sanitized agent' do
    expect do
      post_agent('voice_reply' => true, 'handoff_strategy' => 'none')
    end.not_to change(Autonomia::Agents::Agent, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'voice_reply')
  end

  context 'when the public API actor is a SuperAdmin with account membership' do
    let!(:super_admin) { create(:super_admin) }
    let(:super_admin_headers) { super_admin.create_new_auth_token }

    before do
      create(:account_user, account: account, user: super_admin, role: :administrator)
    end

    operational_keys.each do |key|
      it "rejects #{key} through the public route even for the platform administrator" do
        before_config = agent.reload.config

        patch_config({ key => forbidden_values.fetch(key, true) }, request_headers: super_admin_headers)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => key)
        expect(agent.reload.config).to eq(before_config)
      end
    end
  end

  it 'keeps a foreign agent outside the account scope' do
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_agent = Autonomia::Agents::Agent.create!(
      account: other_account, name: 'Outro agente', agent_type: 'custom', config: { 'voice_reply' => false }
    )
    before_config = foreign_agent.config

    patch_config({ 'handoff_strategy' => 'none' }, agent_id: foreign_agent.id)

    expect(response).to have_http_status(:not_found)
    expect(foreign_agent.reload.config).to eq(before_config)
  end

  it 'does not expose or mutate a system agent through the public scope' do
    system_agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Guia', agent_type: 'custom', config: { 'system_key' => 'guia' }
    )
    before_config = system_agent.config

    patch_config({ 'handoff_strategy' => 'none' }, agent_id: system_agent.id)

    expect(response).to have_http_status(:not_found)
    expect(system_agent.reload.config).to eq(before_config)
  end
end
