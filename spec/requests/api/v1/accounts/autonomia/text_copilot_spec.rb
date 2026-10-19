require 'rails_helper'

# #1872 — o ✨ do editor de e-mail usa a IA do cliente (o copiloto da Autonom.ia). Na gaveta
# Escrever não há conversa: o texto vai sozinho, com a chave da conta e os mesmos gates.
RSpec.describe 'Text copilot (e-mail sem conversa)', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:headers) { agent_user.create_new_auth_token }
  let(:status_url) { "/api/v1/accounts/#{account.id}/autonomia/copilot/status" }
  let(:text_url) { "/api/v1/accounts/#{account.id}/autonomia/copilot/text" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:env) { { AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true', CRM_COPILOT_ENABLED: 'true', CRM_AI_ENABLED: 'true' } }

  around do |example|
    with_modified_env(**env) { example.run }
  end

  def connect_key(target = account)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: target, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
  end

  def post_text(params, request_headers = headers)
    post text_url, params: params, headers: request_headers, as: :json
  end

  describe 'GET status' do
    it 'is available with the copilot on and the account key connected' do
      connect_key

      get status_url, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('available' => true)
    end

    it 'is unavailable without an AI key for the account' do
      get status_url, headers: headers

      expect(response.parsed_body).to eq('available' => false)
    end

    context 'when the copilot kill switch is off' do
      let(:env) { super().merge(CRM_COPILOT_ENABLED: 'false') }

      it 'is unavailable even with the key' do
        connect_key

        get status_url, headers: headers

        expect(response.parsed_body).to eq('available' => false)
      end
    end

    it 'is unavailable when the account has the Autonom.ia agents off' do
      account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })
      connect_key

      get status_url, headers: headers

      expect(response.parsed_body).to eq('available' => false)
    end

    it 'does not answer to someone outside the account' do
      outsider = create(:user, account: create(:account), role: :administrator)

      get status_url, headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST text' do
    before do
      connect_key
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
      allow(client).to receive(:create).and_return({ text: '**Olá**, {{contact.name}} & equipe' })
    end

    it 'rewrites only the text with the account key, in the background, without a conversation' do
      post_text({ task: 'rewrite', draft: 'oi {{contact.name}}', tone: 'direct' })

      expect(response).to have_http_status(:accepted)
      request_id = response.parsed_body['id']
      expect(client).not_to have_received(:create)

      Crm::Ai::InteractiveJob.perform_now(request_id)
      get response.parsed_body['poll_url'], headers: headers

      expect(response.parsed_body).to include('status' => 'done')
      expect(response.parsed_body['result']).to eq(
        'text' => '**Olá**, {{contact.name}} & equipe', 'grounded' => false, 'available' => true, 'error' => nil
      )
      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(hash_including(feature: 'copilot', account: account, credential: hash_including(api_key: 'chave-da-conta')))
      expect(client).to have_received(:create)
        .with(hash_including(input: 'oi {{contact.name}}', instructions: include('direto e objetivo')))
    end

    it 'tells a provider failure apart from a missing key (the screen says try again)' do
      allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'openai_responses_error_503')

      post_text({ task: 'rewrite', draft: 'oi' })
      Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
      get response.parsed_body['poll_url'], headers: headers

      expect(response.parsed_body['result']).to include('available' => false, 'error' => 'ai_failed')
    end

    it 'refines with the fixed instruction' do
      post_text({ task: 'refine', draft: 'texto com erro', instruction: 'corrija só a ortografia' })
      Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])

      expect(client).to have_received(:create).with(hash_including(input: include('corrija só a ortografia', 'texto com erro')))
    end

    it 'refuses the tasks that need a conversation with a clear error' do
      %w[summarize draft].each do |task|
        post_text({ task: task, draft: 'texto' })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'task_needs_conversation')
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'refuses an unknown task' do
      post_text({ task: 'ask_copilot', draft: 'texto' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'task_invalid')
    end

    it 'refuses a text above the server cap before queueing (no silent cut)' do
      allow(Crm::Ai::InteractiveJob).to receive(:perform_later)

      post_text({ task: 'rewrite', draft: 'a' * (Autonomia::Agents::Config::MAX_QUERY_CHARS + 1) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'text_too_long')
      expect(Crm::Ai::InteractiveJob).not_to have_received(:perform_later)
    end

    it 'refuses a free request above its cap' do
      post_text({ task: 'refine', draft: 'texto', instruction: 'a' * 1_001 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'instruction_too_long')
    end

    it 'refuses an empty text' do
      post_text({ task: 'rewrite', draft: '   ' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'draft_missing')
    end

    context 'when the copilot kill switch is off' do
      let(:env) { super().merge(CRM_COPILOT_ENABLED: 'false') }

      it 'is not found' do
        post_text({ task: 'rewrite', draft: 'texto' })

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'is not found when the account has the Autonom.ia agents off' do
      account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })

      post_text({ task: 'rewrite', draft: 'texto' })

      expect(response).to have_http_status(:not_found)
    end

    it 'does not run for someone outside the account' do
      outsider = create(:user, account: create(:account), role: :administrator)

      post_text({ task: 'rewrite', draft: 'texto' }, outsider.create_new_auth_token)

      expect(response).to have_http_status(:unauthorized)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'answers unavailable (no AI call) when the account has no key' do
      Integrations::Hook.where(account: account).destroy_all

      post_text({ task: 'rewrite', draft: 'texto' })
      Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
      get response.parsed_body['poll_url'], headers: headers

      expect(response.parsed_body['result']).to include('available' => false, 'text' => nil)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    describe 'limite de uso por pessoa (LimiteDoCopiloto)' do
      let(:colega) { create(:user, account: account, role: :agent) }
      let(:chaves) { [agent_user, colega].map { |user| "autonomia:copilot:limite:#{user.account_users.find_by(account: account).id}" } }

      before do
        allow(Crm::Ai::InteractiveJob).to receive(:perform_later)
        chaves.each { |chave| Redis::Alfred.delete(chave) }
      end

      after { chaves.each { |chave| Redis::Alfred.delete(chave) } }

      it 'answers 429 too_many_requests on the 21st request in a minute, without touching a colleague' do
        20.times do
          post_text({ task: 'rewrite', draft: 'texto' })
          expect(response).to have_http_status(:accepted)
        end

        post_text({ task: 'rewrite', draft: 'texto' })
        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body).to eq('error' => 'too_many_requests')
        expect(Crm::Ai::InteractiveJob).to have_received(:perform_later).exactly(20).times

        post_text({ task: 'rewrite', draft: 'texto' }, colega.create_new_auth_token)
        expect(response).to have_http_status(:accepted)
      end

      it 'does not spend the quota on refused requests (422)' do
        25.times { post_text({ task: 'rewrite', draft: '  ' }) }
        expect(response).to have_http_status(:unprocessable_entity)

        post_text({ task: 'rewrite', draft: 'texto' })
        expect(response).to have_http_status(:accepted)
      end

      it 'creates the counter with a 60 s deadline' do
        post_text({ task: 'rewrite', draft: 'texto' })

        expect(Redis::Alfred.ttl(chaves.first)).to be_between(1, 60)
      end

      it 'cures a counter left without a deadline on the next request' do
        Redis::Alfred.set(chaves.first, 5)
        expect(Redis::Alfred.ttl(chaves.first)).to eq(-1)

        post_text({ task: 'rewrite', draft: 'texto' })

        expect(response).to have_http_status(:accepted)
        expect(Redis::Alfred.get(chaves.first).to_i).to eq(6)
        expect(Redis::Alfred.ttl(chaves.first)).to be_between(1, 60)
      end

      it 'falls back to 20 when the ENV is not a positive integer' do
        with_modified_env(AUTONOMIA_COPILOT_LIMIT_PER_MINUTE: '0') do
          21.times { post_text({ task: 'rewrite', draft: 'texto' }) }
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(Crm::Ai::InteractiveJob).to have_received(:perform_later).exactly(20).times
      end

      it 'also limits the conversation copilot, sharing the same count' do
        conversation = create(:conversation, account: account)
        create(:inbox_member, inbox: conversation.inbox, user: agent_user)
        20.times { post_text({ task: 'rewrite', draft: 'texto' }) }

        post "/api/v1/accounts/#{account.id}/autonomia/conversations/#{conversation.display_id}/copilot",
             params: { task: 'summarize' }, headers: headers, as: :json

        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end
