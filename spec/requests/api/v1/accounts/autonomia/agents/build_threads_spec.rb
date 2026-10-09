require 'rails_helper'

# Robustez do Construtor (E1–E4): histórico do assistant visível no reload, retry que
# reexecuta a geração, trava de build concorrente e dedupe por client_message_id.
RSpec.describe 'Autonomia agent build threads', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, created_by: administrator) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::Builder::SubmitJob).to receive(:perform_later)
  end

  def post_message(params)
    post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}/messages",
         params: params,
         headers: administrator.create_new_auth_token,
         as: :json
  end

  def post_retry
    post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}/retry",
         headers: administrator.create_new_auth_token,
         as: :json
  end

  describe 'GET /autonomia/build_threads/:id (E1)' do
    it 'returns persisted assistant turns so a reload keeps the interview thread' do
      # Arrange
      thread.append_message!('user', 'Quero um agente de suporte')
      thread.append_message!('assistant', 'Qual o nome do agente?')

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      # Assert
      expect(response).to have_http_status(:success)
      messages = response.parsed_body['payload']['messages']
      expect(messages.pluck('role')).to eq(%w[user assistant])
      expect(messages.last['content']).to eq('Qual o nome do agente?')
    end

    it 'does not expose the thread to a user who can only view agents' do
      thread.append_message!('user', 'Mensagem que não pode vazar')
      viewer = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: ['autonomia_view'])
      viewer.account_users.find_by!(account: account).update!(custom_role: role)

      get "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}",
          headers: viewer.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('payload', 'messages')).to be_nil
      expect(response.body).not_to include('Mensagem que não pode vazar')
    end

    it 'does not resolve a thread from another account' do
      other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      foreign_thread = Autonomia::Agents::BuildThread.create!(account: other_account)

      get "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{foreign_thread.id}",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the linked agent was archived before a user message arrives' do
      linked_agent = Autonomia::Agents::Agent.create!(
        account: account, name: 'Arquivado', agent_type: 'custom', status: :draft, enabled: false
      )
      linked_thread = Autonomia::Agents::BuildThread.create!(account: account, agent: linked_agent)
      Autonomia::Agents::SoftDelete.new(agent: linked_agent, actor: nil, reason: 'stale_draft').perform

      post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{linked_thread.id}/messages",
           params: { message: 'Não deve entrar no histórico.' },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(Array(linked_thread.reload.messages)).to be_empty
    end
  end

  describe 'POST /autonomia/build_threads/:id/messages (E3)' do
    it 'rejects an empty message with the stable message_required code' do
      post_message(message: '')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('message_required')
      expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
    end

    it 'rejects a new turn with 409 build_in_progress while a fresh build is processing' do
      # Arrange
      thread.begin_build!

      # Act
      post_message(message: 'mais uma resposta')

      # Assert
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('build_in_progress')
      expect(Array(thread.reload.messages)).to be_empty
      expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
    end

    it 'accepts a new turn when the processing build is stale' do
      # Arrange
      old_token = thread.begin_build!

      # Act
      travel_to((Autonomia::Agents::BuildThread::STALE_PROCESSING_AFTER + 1.second).from_now) do
        post_message(message: 'destrava, o job morreu')
      end

      # Assert
      expect(response).to have_http_status(:accepted)
      expect(thread.reload.build_token).not_to eq(old_token)
      expect(Autonomia::Agents::Builder::SubmitJob).to have_received(:perform_later).once
    end
  end

  describe 'POST /autonomia/build_threads/:id/messages (E4/T6 idempotency)' do
    it 'answers a replayed turn with the same client_message_id idempotently, without a duplicate turn or job' do
      # Arrange
      cid = SecureRandom.uuid

      # Act — the replay hits while the first build is still processing (double-click / network retry)
      post_message(message: 'Quero um agente de suporte', client_message_id: cid)
      post_message(message: 'Quero um agente de suporte', client_message_id: cid)

      # Assert — 200 with the current state, single persisted turn, single enqueued job
      expect(response).to have_http_status(:ok)
      user_turns = Array(thread.reload.messages).select { |m| m['role'] == 'user' }
      expect(user_turns.size).to eq(1)
      expect(user_turns.first['cid']).to eq(cid)
      expect(Autonomia::Agents::Builder::SubmitJob).to have_received(:perform_later).once
    end

    it 'treats the same client_message_id as a replay even after the build settled' do
      # Arrange
      cid = SecureRandom.uuid
      post_message(message: 'Quero um agente de suporte', client_message_id: cid)
      thread.reload.update!(status: :open)

      # Act
      post_message(message: 'Quero um agente de suporte', client_message_id: cid)

      # Assert
      expect(response).to have_http_status(:ok)
      expect(Array(thread.reload.messages).count { |m| m['role'] == 'user' }).to eq(1)
      expect(Autonomia::Agents::Builder::SubmitJob).to have_received(:perform_later).once
    end
  end

  describe 'POST /autonomia/build_threads/:id/retry (E2)' do
    it 're-enqueues the build for a failed thread with a fresh token' do
      # Arrange
      token = thread.begin_build!
      thread.mark_failed!(token, 'build_error')

      # Act
      post_retry

      # Assert
      expect(response).to have_http_status(:accepted)
      expect(thread.reload).to be_processing
      expect(thread.build_token).not_to eq(token)
      expect(Autonomia::Agents::Builder::SubmitJob).to have_received(:perform_later).with(thread.id, thread.build_token)
    end

    it 'rejects retry with 409 while a fresh build is still processing' do
      # Arrange
      thread.begin_build!

      # Act
      post_retry

      # Assert
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('build_in_progress')
      expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
    end

    it 'rejects retry for a thread that has not failed' do
      # Act
      post_retry

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('retry_unavailable')
      expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
    end
  end
end
