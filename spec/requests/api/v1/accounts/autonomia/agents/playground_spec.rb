require 'rails_helper'

RSpec.describe 'Autonomia agent playground test', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', mode: :guided,
      status: :draft, enabled: false, instruction: 'Responda com clareza.'
    )
  end
  let(:answer) do
    Autonomia::Agents::AnswerResult.new(
      reply: 'Resposta real do teste', confidence: 0.92,
      handoff: { should: false, reason: nil }, answered_from_knowledge: true,
      used_knowledge: [{ id: 11, content: 'Material aprovado', source: 'manual' }]
    )
  end
  let(:playground) { instance_double(Autonomia::Agents::Playground, run: answer) }
  let(:state_store) { Autonomia::Agents::AgentStateStore }
  let(:recorder) { Autonomia::Agents::TestResultRecorder }
  let(:server_session_context) { { id: nil } }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::Playground).to receive(:new).and_return(playground)
    allow(Autonomia::Agents::TestDigest).to receive(:for_agent).and_return(
      tested_digest: "sha256:#{'a' * 64}",
      person_digest: "sha256:#{'p' * 64}",
      material_snapshot_digest: "sha256:#{'b' * 64}",
      material_snapshot_state: 'complete'
    )
    allow(state_store).to receive(:start_pending!) do |**attributes|
      server_session_context[:id] = attributes.fetch(:session_id)
    end
    allow(state_store).to receive(:read) do
      {
        version: 1,
        test: {
          session_id: server_session_context.fetch(:id), state_version: 1, completion: 'completed',
          result_real_ai_deferred: true, valid_for_state: true,
          completed_by_id: 17, completed_by_type: 'AccountUser', completed_by_permission: 'autonomia_manage',
          tested_digest: "sha256:#{'a' * 64}", material_snapshot_digest: "sha256:#{'b' * 64}",
          tested_person_digest: "sha256:#{'p' * 64}",
          skipped_tools: []
        }
      }
    end
    allow(recorder).to receive(:complete!)
  end

  def post_test(user: administrator, target: agent, message: 'Oi, Clara')
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{target.id}/test",
         params: { message: message, history: [{ role: 'user', content: 'contexto' }] },
         headers: user.create_new_auth_token, as: :json
  end

  def poll(request, user: administrator)
    get request.fetch('poll_url'), headers: user.create_new_auth_token, as: :json
  end

  it 'creates a server session and leaves the test pending after the 202 response' do
    expect { post_test }.to have_enqueued_job(Crm::Ai::InteractiveJob)

    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    expect(request).to include('status' => 'pending')
    expect(request['id']).to be_present
    stored = Crm::Ai::InteractiveRequest.read(request['id'])
    expect(stored.dig('inputs', 'session_id')).to be_present
    expect(stored).not_to have_key('test')
    expect(state_store).to have_received(:start_pending!).with(
      hash_including(agent: agent, actor: administrator.account_users.find_by!(account: account),
                     actor_permission: 'autonomia_manage')
    )
  end

  it 'records only the real operation completion and exposes a typed result block on polling' do
    post_test
    request = response.parsed_body

    Crm::Ai::InteractiveJob.perform_now(request['id'])

    expect(playground).to have_received(:run)
    expect(recorder).to have_received(:complete!).with(
      hash_including(
        agent: agent,
        actor: administrator.account_users.find_by!(account: account),
        result: hash_including('reply' => 'Resposta real do teste'),
        result_real_ai_deferred: true
      )
    )

    poll(request)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'done')
    expect(response.parsed_body.fetch('test')).to include(
      'status' => 'completed', 'valid' => true, 'tested_digest' => "sha256:#{'a' * 64}"
    )
    expect(response.body).not_to include('_autonomia_agents_redesign', 'Responda com clareza.')
  end

  it 'lets a viewer run the sandbox but never turns the result into a valid test' do
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    viewer.account_users.find_by!(account: account).update!(custom_role: role)
    allow(state_store).to receive(:read) do
      {
        version: 1,
        test: {
          session_id: server_session_context.fetch(:id), state_version: 1, completion: 'completed',
          result_real_ai_deferred: true, valid_for_state: false,
          completed_by_id: 17, completed_by_type: 'AccountUser', completed_by_permission: 'autonomia_view',
          tested_digest: "sha256:#{'a' * 64}", material_snapshot_digest: "sha256:#{'b' * 64}",
          tested_person_digest: "sha256:#{'p' * 64}", skipped_tools: [
            { slug: 'consultar_cep', name: 'Consultar CEP', code: 'viewer_not_allowed' }
          ]
        }
      }
    end

    post_test(user: viewer)
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])

    expect(recorder).to have_received(:complete!).with(
      hash_including(actor_permission: 'autonomia_view', valid_for_state: false)
    )
    poll(request, user: viewer)
    expect(response).to have_http_status(:ok)
    test = response.parsed_body.fetch('test')
    expect(test).to include('status' => 'completed', 'valid' => false)
    expect(test.fetch('skipped_tools')).to include(include('code' => 'viewer_not_allowed'))
  end

  it 'keeps a real response visible when manage is revoked before completion' do
    post_test
    request = response.parsed_body
    viewer_role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    administrator.account_users.find_by!(account: account).update!(role: 'agent', custom_role: viewer_role)

    Crm::Ai::InteractiveJob.perform_now(request['id'])

    expect(recorder).to have_received(:complete!).with(
      hash_including(actor_permission: 'autonomia_view', valid_for_state: false)
    )
  end

  it 'does not expose an archived or foreign agent through the playground route' do
    archived = Autonomia::Agents::Agent.create!(
      account: account, name: 'Arquivado', agent_type: 'custom', deleted_at: Time.current
    )
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign = Autonomia::Agents::Agent.create!(account: other_account, name: 'Fora', agent_type: 'custom')

    post_test(target: archived)
    expect(response).to have_http_status(:not_found)
    post_test(target: foreign)
    expect(response).to have_http_status(:not_found)
  end

  it 'never treats a failed or partial operation as a completed test' do
    allow(Autonomia::Agents::Playground).to receive(:new).and_raise(StandardError, 'provider unavailable')
    post_test
    request = response.parsed_body

    Crm::Ai::InteractiveJob.perform_now(request['id'])

    expect(recorder).not_to have_received(:complete!)
    poll(request)
    expect(response.parsed_body.fetch('status')).to eq('failed')
    expect(response.parsed_body).not_to have_key('test')
  end
end
