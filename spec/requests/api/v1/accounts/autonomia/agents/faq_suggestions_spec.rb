require 'rails_helper'

# #284 (2b) — revisão das sugestões de FAQ: admin lista/aprova/ignora; agente comum não entra.
RSpec.describe 'Autonomia agent FAQ suggestions', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:conversation) { create(:conversation, account: account) }
  let!(:suggestion) do
    agent.faq_suggestions.create!(account: account, conversation: conversation, question: 'Qual o prazo?', answer: 'Até 5 dias.')
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/faq_suggestions" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return(Autonomia::Agents::Config::EMBEDDING_MODEL_SMALL)
    allow(Autonomia::Agents::EmbeddingService).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::EmbeddingService, embed: Array.new(1536, 0.01)))
  end

  describe 'GET index' do
    it 'lists pending suggestions for an administrator with pagination meta' do
      agent.faq_suggestions.create!(account: account, question: 'Ignorada', answer: 'x', status: :ignored)

      get base_url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['meta']).to include('count' => 1, 'pending_count' => 1, 'current_page' => 1)
      expect(body['payload'].first).to include('question' => 'Qual o prazo?', 'status' => 'pending',
                                               'conversation_display_id' => conversation.display_id)
    end

    it 'filters by status' do
      agent.faq_suggestions.create!(account: account, question: 'Ignorada', answer: 'x', status: :ignored)

      get base_url, params: { status: 'ignored' }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].map { |row| row['question'] }).to eq(['Ignorada'])
    end

    it 'is forbidden for a regular agent' do
      get base_url, headers: agent_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST approve' do
    it 'creates a knowledge entry and marks the suggestion approved' do
      expect do
        post "#{base_url}/#{suggestion.id}/approve", headers: administrator.create_new_auth_token, as: :json
      end.to change(Autonomia::Agents::KnowledgeEntry, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('approved')
      entry = agent.knowledge_entries.last
      expect(entry.content).to include('Qual o prazo?')
      expect(entry.source).to be_present
    end

    it 'saves the edited text and marks the suggestion edited' do
      post "#{base_url}/#{suggestion.id}/approve",
           params: { faq_suggestion: { answer: 'Até 3 dias úteis.' } }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('status' => 'edited', 'answer' => 'Até 3 dias úteis.')
      expect(agent.knowledge_entries.last.content).to include('Até 3 dias úteis.')
    end

    it 'returns 422 when the suggestion was already reviewed' do
      suggestion.update!(status: :ignored)

      post "#{base_url}/#{suggestion.id}/approve", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is forbidden for a regular agent' do
      post "#{base_url}/#{suggestion.id}/approve", headers: agent_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(suggestion.reload).to be_pending
    end
  end

  describe 'POST ignore' do
    it 'marks the suggestion ignored without touching the knowledge base' do
      expect do
        post "#{base_url}/#{suggestion.id}/ignore", headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Autonomia::Agents::KnowledgeEntry, :count)

      expect(response.parsed_body['status']).to eq('ignored')
    end
  end

  it 'exposes and saves the faq_suggestions toggle through the agent API' do
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { config: { faq_suggestions: true } } }, headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('config', 'faq_suggestions')).to be(true)
    expect(agent.reload.faq_suggestions_enabled?).to be(true)
  end
end
