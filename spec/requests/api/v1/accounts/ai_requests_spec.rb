require 'rails_helper'

RSpec.describe 'Interactive AI requests', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/conversations/#{conversation.display_id}/copilot" }
  let(:result) { Autonomia::Copilot::ConversationCopilot::Result.new(text: 'resposta', grounded: true, available: true) }
  let(:service) { instance_double(Autonomia::Copilot::ConversationCopilot, perform: result) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true', CRM_COPILOT_ENABLED: 'true',
                      CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before { allow(Autonomia::Copilot::ConversationCopilot).to receive(:new).and_return(service) }

  it 'returns immediately, performs in a job and preserves the response fields' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    expect(service).not_to have_received(:perform)
    get request['poll_url'], headers: headers
    expect(response.parsed_body['status']).to eq('pending')

    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body).to include('status' => 'done', 'result' => result.to_h.stringify_keys)
  end

  it 'does not expose the result to another member of the same account' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    poll_url = response.parsed_body['poll_url']
    other = create(:user, account: account, role: :administrator)
    get poll_url, headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'does not expose the result in another account' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    id = response.parsed_body['id']
    other_account = create(:account)
    create(:account_user, account: other_account, user: user, role: :administrator)
    get "/api/v1/accounts/#{other_account.id}/ai_requests/#{id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not call the model after access to the conversation is revoked' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    agent_headers = agent.create_new_auth_token
    post url, params: { task: 'summarize' }, headers: agent_headers, as: :json
    request = response.parsed_body
    Crm::InboxSetting.create!(account: account, inbox: conversation.inbox, visibility_mode: :assigned_only)

    Crm::Ai::InteractiveJob.perform_now(request['id'])
    expect(service).not_to have_received(:perform)
    expect(Crm::Ai::InteractiveRequest.read(request['id'])['status']).to eq('failed')
    get request['poll_url'], headers: agent_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'marks failure without retrying the whole operation or exposing the exception' do
    allow(service).to receive(:perform).and_raise(StandardError, 'private diagnostic')
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body['status']).to eq('failed')
    expect(response.body).not_to include('private diagnostic')
    expect(service).to have_received(:perform).once
  end

  it 'does not execute queued work for an account suspended after submission' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    request = response.parsed_body
    account.update!(status: :suspended)
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    expect(service).not_to have_received(:perform)
    expect(Crm::Ai::InteractiveRequest.read(request['id'])['status']).to eq('failed')
  end

  it 'does not replay an already claimed operation after a worker restart' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    request = response.parsed_body
    expect(Crm::Ai::InteractiveRequest.claim(request['id'])).to be_truthy
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    expect(service).not_to have_received(:perform)
  end

  it 'does not recreate an expired request' do
    post url, params: { task: 'summarize' }, headers: headers, as: :json
    request = response.parsed_body
    Redis::Alfred.delete("#{Crm::Ai::InteractiveRequest::PREFIX}#{request['id']}")
    Crm::Ai::InteractiveRequest.finish(request['id'], status: 'done', result: { text: 'late' })
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response).to have_http_status(:not_found)
    expect(service).not_to have_received(:perform)
  end

  context 'when testing an Autonomia agent' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) do
      Autonomia::Agents::Agent.create!(
        account: account, name: 'Clara', agent_type: 'custom', status: :draft,
        enabled: false, instruction: 'Responda com clareza.'
      )
    end
    let(:answer) do
      Autonomia::Agents::AnswerResult.new(
        reply: 'Resposta real', confidence: 0.9,
        handoff: { should: false, reason: nil }, answered_from_knowledge: false
      )
    end
    let(:playground) { instance_double(Autonomia::Agents::Playground, run: answer) }
    let(:state_store) { Autonomia::Agents::AgentStateStore }
    let(:recorder) { Autonomia::Agents::TestResultRecorder }

    around do |example|
      with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
        example.run
      end
    end

    before do
      allow(Autonomia::Agents::Playground).to receive(:new).and_return(playground)
      allow(state_store).to receive(:start_pending!)
      allow(state_store).to receive(:read).and_return(
        version: 1,
        test: { session_id: 'server-session-1', completion: 'completed', valid: true, skipped_tools: [] }
      )
      allow(recorder).to receive(:complete!)
    end

    def post_agent_test(user: administrator)
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/test",
           params: { message: 'Teste agora' }, headers: user.create_new_auth_token, as: :json
    end

    it 'keeps the polling identity bound to the creator, account and integration context' do
      post_agent_test
      request = response.parsed_body
      other_member = create(:user, account: account, role: :administrator)
      other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      create(:account_user, account: other_account, user: administrator, role: :administrator)

      get request.fetch('poll_url'), headers: other_member.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get "/api/v1/accounts/#{other_account.id}/ai_requests/#{request['id']}",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'does not execute or reveal a queued result after view permission is revoked' do
      viewer = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: ['autonomia_view'])
      viewer_account_user = viewer.account_users.find_by!(account: account)
      viewer_account_user.update!(custom_role: role)

      post_agent_test(user: viewer)
      request = response.parsed_body
      role.update!(permissions: [])

      Crm::Ai::InteractiveJob.perform_now(request['id'])

      expect(playground).not_to have_received(:run)
      expect(Crm::Ai::InteractiveRequest.read(request['id']).fetch('status')).to eq('failed')
      get request.fetch('poll_url'), headers: viewer.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not execute the real operation again when the result is polled repeatedly' do
      post_agent_test
      request = response.parsed_body
      Crm::Ai::InteractiveJob.perform_now(request['id'])

      get request.fetch('poll_url'), headers: administrator.create_new_auth_token, as: :json
      get request.fetch('poll_url'), headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(playground).to have_received(:run).once
      expect(recorder).to have_received(:complete!).once
    end

    it 'keeps an expired polling request gone instead of recreating its test state' do
      post_agent_test
      request = response.parsed_body
      Redis::Alfred.delete("#{Crm::Ai::InteractiveRequest::PREFIX}#{request['id']}")

      Crm::Ai::InteractiveJob.perform_now(request['id'])
      get request.fetch('poll_url'), headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(recorder).not_to have_received(:complete!)
    end
  end
end
