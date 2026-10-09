require 'rails_helper'

RSpec.describe 'Agent test state through the real async request', type: :request do
  let(:account) { create(:account, locale: 'pt_BR', internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Synthetic', agent_type: 'custom',
                                     instruction: 'Private synthetic instruction')
  end
  let(:answer) do
    Autonomia::Agents::AnswerResult.new(reply: 'Synthetic model answer', confidence: 0.9,
                                        handoff: { should: false, reason: nil })
  end
  let(:answerer) { instance_double(Autonomia::Agents::Answerer, answer: answer) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before { allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer) }

  def submit_test
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/test",
         params: { message: 'Synthetic question' }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    response.parsed_body
  end

  def list_state
    get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('payload').sole.fetch('state')
  end

  it 'persists a pending session, becomes E4 only after the job and invalidates on a real name change' do
    request = submit_test
    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'completion')).to eq('pending')
    expect(list_state).to include('code' => 'E3')

    Crm::Ai::InteractiveJob.perform_now(request.fetch('id'))
    metadata = agent.reload.config.dig('_autonomia_agents_redesign', 'test')
    expect(metadata).to include('completion' => 'completed', 'result_real_ai_deferred' => true,
                                'completed_by_permission' => 'autonomia_manage')
    expect(metadata.to_json).not_to include('Synthetic model answer', 'Synthetic question', 'Private synthetic instruction')
    expect(list_state).to include('code' => 'E4', 'continuation' => 'live')

    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", params: { agent: { name: 'Updated synthetic' } },
                                                                         headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(list_state).to include('code' => 'E3', 'test_invalidated_by' => 'person')
  end

  it 'updates the native channel identity when a tested draft changes its name' do
    inbox = create(:inbox, account: account)
    bot = AgentBot.create!(account: account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(account: account, agent: agent, inbox: inbox, agent_bot: bot)
    request = submit_test
    Crm::Ai::InteractiveJob.perform_now(request.fetch('id'))

    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", params: { agent: { name: 'New identity' } },
                                                                         headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(agent.reload.agent_inboxes.kept.sole.agent_bot.name).to eq('New identity')
    expect(list_state).to include('code' => 'E3', 'test_invalidated_by' => 'person')
  end

  it 'rechecks permissions at completion and does not promote an editor who lost manage to E4' do
    request = submit_test
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    administrator.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)

    Crm::Ai::InteractiveJob.perform_now(request.fetch('id'))

    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'completed_by_permission')).to eq('autonomia_view')
    expect(list_state).to include('code' => 'E3')
    get request.fetch('poll_url'), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('result').fetch('reply')).to eq('Synthetic model answer')
  end

  it 'does not overwrite a later session or mark a changed digest as tested by an earlier job' do
    old_request = submit_test
    new_request = submit_test
    current_session = agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'session_id')
    Crm::Ai::InteractiveJob.perform_now(old_request.fetch('id'))
    expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
      'session_id' => current_session, 'completion' => 'pending'
    )
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", params: { agent: { name: 'Changed after submission' } },
                                                                         headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    Crm::Ai::InteractiveJob.perform_now(new_request.fetch('id'))
    expect(list_state).to include('code' => 'E3')
  end

  it 'does not record a valid test when the Redis request expires during the operation' do
    request = submit_test
    request_key = "#{Crm::Ai::InteractiveRequest::PREFIX}#{request.fetch('id')}"
    playground = instance_double(Autonomia::Agents::Playground)
    allow(playground).to receive(:run) do
      Redis::Alfred.delete(request_key)
      answer
    end
    allow(Autonomia::Agents::Playground).to receive(:new).and_return(playground)

    Crm::Ai::InteractiveJob.perform_now(request.fetch('id'))

    metadata = agent.reload.config.dig('_autonomia_agents_redesign', 'test').to_h
    expect(metadata).not_to include('completion' => 'completed', 'valid_for_state' => true)
    expect(Crm::Ai::InteractiveRequest.read(request.fetch('id'))).to be_nil
  end

  it 'does not expose the current session proof when polling an older completed request' do
    first_request = submit_test
    Crm::Ai::InteractiveJob.perform_now(first_request.fetch('id'))

    second_request = submit_test
    Crm::Ai::InteractiveJob.perform_now(second_request.fetch('id'))
    second_test = agent.reload.config.dig('_autonomia_agents_redesign', 'test')

    get first_request.fetch('poll_url'), headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('status')).to eq('done')
    expect(response.parsed_body.fetch('test')).to include('status' => 'stale', 'valid' => false)
    expect(response.parsed_body.fetch('test')).not_to have_key('tested_digest')
    expect(response.parsed_body.fetch('test')).not_to have_key('material_snapshot_digest')

    get second_request.fetch('poll_url'), headers: headers, as: :json
    expect(response.parsed_body.fetch('test')).to include(
      'status' => 'completed', 'valid' => true,
      'tested_digest' => second_test.fetch('tested_digest')
    )
  end
end
