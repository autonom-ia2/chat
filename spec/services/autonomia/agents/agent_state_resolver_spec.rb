require 'rails_helper'

RSpec.describe Autonomia::Agents::AgentStateResolver, type: :service do
  let(:resolver) { described_class }
  let(:current_digest) { "sha256:#{'a' * 64}" }
  let(:current_person_digest) { "sha256:#{'b' * 64}" }
  let(:current_material_digest) { "sha256:#{'c' * 64}" }
  let(:guided_agent) do
    {
      archived: false, status: 'draft', enabled: false, mode: 'guided',
      instruction_present: true, actuation: 'external', has_material: false
    }
  end

  def resolve(agent:, **options)
    resolver.resolve(
      agent: agent,
      thread: options.fetch(:thread, {}),
      test: options.fetch(:test, {}),
      current_digest: options.fetch(:digest, current_digest),
      current_person_digest: options.fetch(:person_digest, current_person_digest),
      current_material_digest: options.fetch(:material_digest, current_material_digest),
      retention_hours: 48,
      session_id: 'session-1',
      state_version: 1
    )
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_raise('state resolver must not query ActiveRecord')
  end

  it 'resolves the unfinished guided journey as E1 and then E2 from typed thread facts' do
    unfinished = guided_agent.merge(instruction_present: false)

    expect(resolve(agent: unfinished, thread: {
                     user_response: false, needs_more_info: false,
                     with_knowledge: true, no_materials_declared: true
                   }))
      .to include(code: 'E1', continuation: 'tell', retention_hours: 48)

    expect(resolve(agent: unfinished, thread: {
                     user_response: true, needs_more_info: true,
                     with_knowledge: true, no_materials_declared: false
                   }))
      .to include(code: 'E2', continuation: 'tell')

    expect(resolve(agent: unfinished.merge(has_material: true), thread: {
                     user_response: false, needs_more_info: false,
                     with_knowledge: true, no_materials_declared: false
                   }))
      .to include(code: 'E2', continuation: 'tell')
  end

  it 'keeps a manual agent at E2m without a reaper retention deadline' do
    manual = guided_agent.merge(mode: 'manual', instruction_present: false)

    expect(resolve(agent: manual, thread: { user_response: true, needs_more_info: false }))
      .to include(code: 'E2m', continuation: 'manual', retention_hours: nil)
  end

  it 'uses E3 for legacy instructions and for a current instruction without a valid test' do
    expect(resolve(agent: guided_agent, thread: {}, test: {}))
      .to include(code: 'E3', continuation: 'test')

    expect(resolve(agent: guided_agent, thread: { user_response: true, needs_more_info: false }, test: {}))
      .to include(code: 'E3', continuation: 'test')

    expect(resolve(agent: guided_agent, thread: { user_response: true, needs_more_info: false }, test: {
                     completion: 'completed', tested_digest: nil
                   }))
      .to include(code: 'E3', continuation: 'test')
  end

  it 'uses E4 for a real completed editor test even while material status is provisional' do
    test = {
      completion: 'completed', result_real_ai_deferred: true,
      session_id: 'session-1', tested_digest: current_digest,
      tested_person_digest: current_person_digest,
      material_snapshot_digest: current_material_digest,
      material_snapshot_state: 'partial', state_version: 1,
      completed_by_id: 17, completed_by_type: 'AccountUser', completed_by_permission: 'autonomia_manage',
      skipped_tools: [{ slug: 'consultar_cep', name: 'Consultar CEP', code: 'not_in_test' }]
    }

    expect(resolve(agent: guided_agent, thread: { user_response: true, needs_more_info: false }, test: test))
      .to include(code: 'E4', continuation: 'live', valid: true)
  end

  it 'keeps E5 and E6 ahead of post-test changes and does not force a second test' do
    completed = {
      completion: 'completed', result_real_ai_deferred: true,
      session_id: 'session-1', state_version: 1,
      tested_digest: "sha256:#{'d' * 64}", tested_person_digest: current_person_digest,
      material_snapshot_digest: "sha256:#{'e' * 64}",
      completed_by_id: 17, completed_by_type: 'AccountUser', completed_by_permission: 'autonomia_manage'
    }

    expect(resolve(agent: guided_agent.merge(status: 'active', enabled: true), test: completed))
      .to include(code: 'E5', continuation: 'open')
    expect(resolve(agent: guided_agent.merge(status: 'paused', enabled: false), test: completed))
      .to include(code: 'E6', continuation: 'open')

    # Algumas contas antigas representam a pausa como active + enabled=false; o leitor trata a
    # combinação como E6 sem alterar o status persistido nem exigir novo teste (D24).
    expect(resolve(agent: guided_agent.merge(status: 'active', enabled: false), test: completed))
      .to include(code: 'E6', continuation: 'open')
  end

  it 'marks digest and material changes with the correct invalidation reason' do
    person_changed = {
      completion: 'completed', result_real_ai_deferred: true,
      session_id: 'session-1', state_version: 1,
      tested_digest: "sha256:#{'d' * 64}",
      tested_person_digest: "sha256:#{'e' * 64}",
      material_snapshot_digest: current_material_digest,
      completed_by_id: 17, completed_by_type: 'AccountUser', completed_by_permission: 'autonomia_manage'
    }
    material_changed = person_changed.merge(
      tested_person_digest: current_person_digest,
      material_snapshot_digest: "sha256:#{'f' * 64}"
    )

    expect(resolve(agent: guided_agent, test: person_changed, digest: current_digest))
      .to include(code: 'E3', invalidated_by: 'person')

    expect(resolve(agent: guided_agent, test: material_changed, digest: "sha256:#{'g' * 64}"))
      .to include(code: 'E3', invalidated_by: 'material')

    both_changed = material_changed.merge(tested_person_digest: "sha256:#{'h' * 64}")
    expect(resolve(agent: guided_agent, test: both_changed, digest: "sha256:#{'i' * 64}"))
      .to include(code: 'E3', invalidated_by: 'person')
  end

  it 'does not let a viewer completion become E4 and rejects stale or partial results' do
    viewer_test = {
      completion: 'completed', result_real_ai_deferred: true,
      session_id: 'session-1', state_version: 1,
      completed_by_id: 17, completed_by_type: 'AccountUser',
      tested_digest: current_digest, tested_person_digest: current_person_digest,
      material_snapshot_digest: current_material_digest,
      completed_by_permission: 'autonomia_view'
    }
    expect(resolve(agent: guided_agent, test: viewer_test)).to include(code: 'E3', continuation: 'test')

    stale = viewer_test.merge(completion: 'stale', session_id: 'old-session')
    expect(resolve(agent: guided_agent, test: stale)).to include(code: 'E3', continuation: 'test')

    without_actor = viewer_test.except(:completed_by_id, :completed_by_type)
    expect(resolve(agent: guided_agent, test: without_actor)).to include(code: 'E3', continuation: 'test')

    without_session = viewer_test.except(:session_id)
    expect(resolve(agent: guided_agent, test: without_session)).to include(code: 'E3', continuation: 'test')
  end

  it 'omits archived agents before any state is presented' do
    expect(resolve(agent: guided_agent.merge(archived: true))).to include(code: 'archived')
  end
end
