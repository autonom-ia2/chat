require 'rails_helper'

RSpec.describe Autonomia::Agents::TestResultRecorder, type: :service do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:editor) { create(:user, account: account, role: :administrator) }
  let(:editor_account_user) { editor.account_users.find_by!(account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', status: :draft, enabled: false,
      instruction: 'Atenda com clareza.'
    )
  end
  let(:session_id) { 'server-session-1' }
  let(:request_data) do
    {
      'account_id' => account.id,
      'account_user_id' => editor_account_user.id,
      'operation' => 'agent_test',
      'status' => 'done',
      'inputs' => { 'agent_id' => agent.id, 'session_id' => session_id }
    }
  end
  let(:result) do
    {
      'reply' => 'resposta real',
      'confidence' => 0.91,
      'answered_from_knowledge' => true,
      'skipped_tools' => [
        { 'slug' => 'consultar_cep', 'name' => 'Consultar CEP', 'code' => 'not_in_test', 'args' => { 'cpf' => 'segredo' } }
      ]
    }
  end
  let(:store) { Autonomia::Agents::AgentStateStore }
  let(:recorder) { described_class }
  let(:current_digest) { "sha256:#{'a' * 64}" }
  let(:current_person_digest) { "sha256:#{'b' * 64}" }
  let(:current_material_digest) { "sha256:#{'c' * 64}" }

  before do
    allow(store).to receive(:read).with(agent: agent).and_return(
      version: 1,
      test: { session_id: session_id, completion: 'pending' }
    )
    allow(store).to receive(:complete!)
    allow(store).to receive(:fail!)
  end

  def record(actor: editor_account_user, permission: 'autonomia_manage', data: request_data, output: result)
    recorder.complete!(
      request: data,
      agent: agent,
      actor: actor,
      actor_permission: permission,
      result: output,
      current_digest: current_digest,
      current_person_digest: current_person_digest,
      material_snapshot_digest: current_material_digest,
      material_snapshot_state: 'partial'
    )
  end

  it 'records only a completed real response after the deferred operation finishes' do
    record

    expect(store).to have_received(:complete!).with(
      hash_including(
        agent: agent,
        session_id: session_id,
        actor: editor_account_user,
        actor_permission: 'autonomia_manage',
        tested_digest: current_digest,
        tested_person_digest: current_person_digest,
        material_snapshot_digest: current_material_digest,
        material_snapshot_state: 'partial',
        result_real_ai_deferred: true,
        writes_external: false,
        skipped_tools: [{ 'slug' => 'consultar_cep', 'name' => 'Consultar CEP', 'code' => 'not_in_test' }]
      )
    )
  end

  it 'persists writes_external only when the server result carries true' do
    record(output: result.merge('writes_external' => true))

    expect(store).to have_received(:complete!).with(hash_including(writes_external: true))
  end

  it 'exposes the persisted boolean in the safe public test result' do
    allow(store).to receive(:read).with(agent: agent).and_return(
      version: 1,
      test: { session_id: session_id, completion: 'completed', writes_external: true },
      test_invalidated_by: nil
    )
    allow(Autonomia::Agents::AgentStateResolver).to receive(:test_result)
      .and_return(valid: true, invalidated_by: nil)

    payload = recorder.public_payload(
      agent: agent,
      current_digests: { aggregate: current_digest, person: current_person_digest, material: current_material_digest },
      session_id: session_id
    )

    expect(payload).to include('writes_external' => true)
  end

  it 'ignores a writes_external value supplied inside client inputs' do
    record(
      data: request_data.deep_merge('inputs' => { 'writes_external' => true })
    )

    expect(store).to have_received(:complete!).with(hash_including(writes_external: false))
  end

  it 'allows a viewer to see the result but records the effective permission so it cannot satisfy E4' do
    record(permission: 'autonomia_view')

    expect(store).to have_received(:complete!).with(
      hash_including(actor_permission: 'autonomia_view', valid_for_state: false)
    )
  end

  it 'does not complete an operation when manage is lost before the result is recorded' do
    record(
      permission: 'autonomia_view',
      output: result.merge(
        'skipped_tools' => [
          {
            'slug' => 'consultar_cep', 'name' => 'Consultar CEP', 'code' => 'viewer_not_allowed',
            'url' => 'https://private.example', 'token' => 'never-persist'
          }
        ]
      )
    )

    expect(store).to have_received(:complete!).with(
      hash_including(
        actor_permission: 'autonomia_view',
        valid_for_state: false,
        skipped_tools: [{ 'slug' => 'consultar_cep', 'name' => 'Consultar CEP', 'code' => 'viewer_not_allowed' }]
      )
    )
  end

  it 'marks a completion from an older session stale without replacing the current pending session' do
    allow(store).to receive(:read).with(agent: agent).and_return(
      version: 1, test: { session_id: 'new-session', completion: 'pending' }
    )

    expect { record(data: request_data.deep_merge('inputs' => { 'session_id' => 'old-session' })) }
      .to raise_error(Autonomia::Agents::TestResultRecorder::StaleSession)
    expect(store).not_to have_received(:complete!)
  end

  it 'records failed, timed out and partial results as non-completions' do
    statuses = {
      'failed' => 'error', 'timeout' => 'error', 'partial' => 'no_response',
      'no_response' => 'no_response', 'rate_limited' => 'rate_limited'
    }
    failures = []
    allow(store).to receive(:fail!) { |**kwargs| failures << kwargs }

    statuses.each_key do |status|
      record(data: request_data.merge('status' => status), output: result.merge('status' => status))
    end

    expect(failures.map { |failure| failure.fetch(:completion) }).to eq(statuses.values)
    expect(failures).to all(satisfy { |failure| failure[:agent] == agent && failure[:session_id] == session_id })
    expect(store).not_to have_received(:complete!)
  end

  it 'marks a provider error as failed without persisting private result fields' do
    allow(store).to receive(:read).with(agent: agent).and_call_original
    allow(store).to receive(:fail!).and_call_original
    store.start_pending!(
      agent: agent, session_id: session_id, actor: editor_account_user, actor_permission: 'autonomia_manage'
    )

    record(output: result.merge(
      'completion' => 'completed', 'error' => 'provider private error', 'raw_prompt' => 'hidden'
    ))

    expect(store).to have_received(:fail!).with(
      agent: agent, session_id: session_id, completion: 'error'
    )
    expect(store).not_to have_received(:complete!)

    persisted_test = agent.reload.config.fetch('_autonomia_agents_redesign').fetch('test')
    expect(persisted_test).to include('completion' => 'error', 'result_real_ai_deferred' => false)
    expect(persisted_test).not_to include('result', 'error', 'raw_prompt')
  end

  it 'rejects a request whose actor or agent belongs to another account before writing state' do
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    other_user = create(:user, account: other_account, role: :administrator)
    foreign_actor = other_user.account_users.find_by!(account: other_account)

    expect do
      record(actor: foreign_actor)
    end.to raise_error(Autonomia::Agents::TestResultRecorder::AccountMismatch)
    expect(store).not_to have_received(:complete!)
  end

  it 'lê no payload público a recusa segura da especialista Lia pelo estado persistido' do
    Autonomia::Agents::Specialist.create!(
      agent: agent, account: account, name: 'Cotação de automóvel', slug: 'cotacao_auto',
      description: 'Cota automóvel.', instruction: 'Você cota automóvel.'
    )
    allow(store).to receive(:read).and_call_original
    allow(store).to receive(:read).with(agent: agent).and_call_original
    allow(store).to receive(:start_pending!).and_call_original
    allow(store).to receive(:complete!).and_call_original
    allow(store).to receive(:fail!).and_call_original
    allow(Autonomia::Agents::AgentStateResolver).to receive(:test_result)
      .and_return(valid: true, invalidated_by: nil)

    store.start_pending!(
      agent: agent, session_id: session_id, actor: editor_account_user, actor_permission: 'autonomia_manage'
    )
    record(
      output: result.merge(
        'skipped_tools' => [
          { 'slug' => 'consultar_cotacao_auto', 'name' => 'consultar_cotacao_auto', 'code' => 'not_in_test' }
        ]
      )
    )

    payload = recorder.public_payload(
      agent: agent,
      current_digests: { aggregate: current_digest, person: current_person_digest, material: current_material_digest },
      session_id: session_id
    )

    expect(payload.fetch('skipped_tools')).to eq(
      [{ 'slug' => 'consultar_cotacao_auto', 'name' => 'consultar_cotacao_auto', 'code' => 'not_in_test' }]
    )
  end
end
