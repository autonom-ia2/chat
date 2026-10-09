require 'rails_helper'

RSpec.describe Autonomia::Agents::AgentStateStore, type: :service do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:editor) { create(:user, account: account, role: :administrator) }
  let(:editor_account_user) { editor.account_users.find_by!(account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Clara',
      agent_type: 'custom',
      status: :draft,
      enabled: false,
      config: {
        'public_marker' => 'preserve-me',
        'with_knowledge' => true,
        'autonomia_agents_redesign' => { 'calculated' => 'do-not-touch' }
      }
    )
  end
  let(:store) { described_class }
  let(:session_id) { 'server-session-1' }
  let(:tested_digest) { "sha256:#{'a' * 64}" }
  let(:person_digest) { "sha256:#{'b' * 64}" }
  let(:material_digest) { "sha256:#{'c' * 64}" }

  it 'merges pending state under one private namespace while preserving public config' do
    expect(agent).to receive(:with_lock).and_call_original

    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_view')

    config = agent.reload.config
    expect(config).to include('public_marker' => 'preserve-me', 'with_knowledge' => true)
    expect(config.dig('autonomia_agents_redesign', 'calculated')).to eq('do-not-touch')
    expect(config.dig('_autonomia_agents_redesign', 'version')).to eq(1)
    expect(config.dig('_autonomia_agents_redesign', 'test')).to include(
      'session_id' => session_id,
      'completion' => 'pending',
      'writes_external' => false
    )
    expect(config.dig('_autonomia_agents_redesign', 'test')).not_to include('tested_digest', 'completed_at')
  end

  it 'records only a completed server result with actor permission and safe skipped tools' do
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    store.complete!(
      agent: agent,
      session_id: session_id,
      actor: editor_account_user,
      actor_permission: 'autonomia_manage',
      result: { 'reply' => 'resposta real', 'raw_prompt' => 'segredo' },
      tested_digest: tested_digest,
      tested_person_digest: person_digest,
      material_snapshot_digest: material_digest,
      material_snapshot_state: 'partial',
      writes_external: true,
      skipped_tools: [
        { slug: 'consultar_cep', name: 'Consultar CEP', code: 'not_in_test', args: { phone: '+5511999999999' }, secret: 'no-log' }
      ]
    )

    test = agent.reload.config.dig('_autonomia_agents_redesign', 'test')
    expect(test).to include(
      'session_id' => session_id,
      'completion' => 'completed',
      'result_real_ai_deferred' => true,
      'completed_by_id' => editor_account_user.id,
      'completed_by_type' => 'AccountUser',
      'completed_by_permission' => 'autonomia_manage',
      'tested_digest' => tested_digest,
      'tested_person_digest' => person_digest,
      'material_snapshot_digest' => material_digest,
      'material_snapshot_state' => 'partial',
      'writes_external' => true
    )
    expect(test['skipped_tools']).to eq(
      [{ 'slug' => 'consultar_cep', 'name' => 'Consultar CEP', 'code' => 'not_in_test' }]
    )
    expect(test.to_json).not_to include('raw_prompt', 'phone', 'no-log')
  end

  it 'reduces a non-boolean writes_external value to the safe default' do
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    store.complete!(
      agent: agent,
      session_id: session_id,
      actor: editor_account_user,
      actor_permission: 'autonomia_manage',
      result: { 'reply' => 'resposta' },
      tested_digest: tested_digest,
      tested_person_digest: person_digest,
      material_snapshot_digest: material_digest,
      material_snapshot_state: 'complete',
      skipped_tools: [],
      writes_external: 'true'
    )

    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'writes_external')).to be(false)
  end

  it 'rejects an unknown or mislabeled skipped tool before writing private state' do
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    expect do
      store.complete!(
        agent: agent,
        session_id: session_id,
        actor: editor_account_user,
        actor_permission: 'autonomia_manage',
        result: { 'reply' => 'resposta' },
        tested_digest: tested_digest,
        tested_person_digest: person_digest,
        material_snapshot_digest: material_digest,
        material_snapshot_state: 'complete',
        skipped_tools: [{ slug: 'ferramenta_inventada', name: 'Ferramenta falsa', code: 'not_in_test',
                          url: 'https://private.example', args: { cpf: 'segredo' } }]
      )
    end.to raise_error(Autonomia::Agents::AgentStateStore::InvalidState)

    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
      'session_id' => session_id, 'completion' => 'pending'
    )

    expect do
      store.complete!(
        agent: agent,
        session_id: session_id,
        actor: editor_account_user,
        actor_permission: 'autonomia_manage',
        result: { 'reply' => 'resposta' },
        tested_digest: tested_digest,
        tested_person_digest: person_digest,
        material_snapshot_digest: material_digest,
        material_snapshot_state: 'complete',
        skipped_tools: [{ slug: 'consultar_cep', name: 'Nome que veio do modelo', code: 'not_in_test' }]
      )
    end.to raise_error(Autonomia::Agents::AgentStateStore::InvalidState)
  end

  it 'accepts a known HTTP tool and stores only its public catalog identity' do
    http_tool = Autonomia::Agents::Tool.create!(
      account: account,
      agent: agent,
      name: 'Consulta de estoque',
      slug: 'consulta_estoque',
      endpoint_url: 'https://example.com/lookup',
      param_schema: []
    )
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    store.complete!(
      agent: agent,
      session_id: session_id,
      actor: editor_account_user,
      actor_permission: 'autonomia_manage',
      result: { 'reply' => 'resposta' },
      tested_digest: tested_digest,
      tested_person_digest: person_digest,
      material_snapshot_digest: material_digest,
      material_snapshot_state: 'complete',
      skipped_tools: [{ slug: http_tool.slug, name: http_tool.name, code: 'viewer_not_allowed',
                        args: { secret: 'never-persist' } }]
    )

    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'skipped_tools')).to eq(
      [{ 'slug' => 'consulta_estoque', 'name' => 'Consulta de estoque', 'code' => 'viewer_not_allowed' }]
    )
  end

  it 'rejects a completion from a stale session without overwriting the current pending test' do
    store.start_pending!(agent: agent, session_id: 'new-session', actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    expect do
      store.complete!(
        agent: agent,
        session_id: 'old-session',
        actor: editor_account_user,
        actor_permission: 'autonomia_manage',
        result: { 'reply' => 'atrasada' },
        tested_digest: "sha256:#{'d' * 64}",
        tested_person_digest: person_digest,
        material_snapshot_digest: "sha256:#{'e' * 64}",
        material_snapshot_state: 'complete',
        skipped_tools: []
      )
    end.to raise_error(Autonomia::Agents::AgentStateStore::StaleSession)

    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
      'session_id' => 'new-session', 'completion' => 'pending'
    )
  end

  it 'invalidates only the test block and preserves configuration and its version' do
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_manage')
    store.complete!(
      agent: agent,
      session_id: session_id,
      actor: editor_account_user,
      actor_permission: 'autonomia_manage',
      result: { 'reply' => 'resposta' },
      tested_digest: tested_digest,
      tested_person_digest: person_digest,
      material_snapshot_digest: material_digest,
      material_snapshot_state: 'complete',
      skipped_tools: []
    )

    store.invalidate!(agent: agent, reason: 'person')

    namespace = agent.reload.config.fetch('_autonomia_agents_redesign')
    expect(namespace).to include('version' => 1, 'test_invalidated_by' => 'person')
    expect(namespace['test']).to be_nil
    expect(agent.config).to include('public_marker' => 'preserve-me', 'with_knowledge' => true)
  end

  it 'does not erase a newer test when a material writer has an older session snapshot' do
    store.start_pending!(agent: agent, session_id: 'writer-session', actor: editor_account_user,
                         actor_permission: 'autonomia_manage')
    store.start_pending!(agent: agent, session_id: 'new-session', actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    expect(store.invalidate_if_current!(agent: agent, reason: 'material', session_id: 'writer-session'))
      .to be(false)
    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
      'session_id' => 'new-session', 'completion' => 'pending'
    )
  end

  it 'invalidates the session that the material writer actually observed' do
    store.start_pending!(agent: agent, session_id: 'writer-session', actor: editor_account_user,
                         actor_permission: 'autonomia_manage')

    expect(store.invalidate_if_current!(agent: agent, reason: 'material', session_id: 'writer-session'))
      .to be(true)
    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to be_nil
    expect(agent.config.dig('_autonomia_agents_redesign', 'test_invalidated_by')).to eq('material')
  end

  it 'returns a typed private projection without exposing the entire config blob' do
    store.start_pending!(agent: agent, session_id: session_id, actor: editor_account_user,
                         actor_permission: 'autonomia_view')

    projection = store.read(agent: agent)

    expect(projection).to include(
      version: 1,
      test: include(session_id: session_id, completion: 'pending', writes_external: false)
    )
    expect(projection).not_to have_key(:public_marker)
    expect(projection.to_json).not_to include('preserve-me', 'calculated')
  end

  it 'does not interpret a namespace from an unsupported schema version' do
    agent.update!(
      config: {
        '_autonomia_agents_redesign' => {
          'version' => 2,
          'test' => { 'completion' => 'completed', 'state_version' => 2, 'tested_digest' => tested_digest }
        }
      }
    )

    projection = store.read(agent: agent)

    expect(projection).to include(version: 2, test: {})
  end
end
