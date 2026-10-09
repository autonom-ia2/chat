require 'rails_helper'

RSpec.describe 'Agent test write warning through the asynchronous request', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Synthetic agent', agent_type: 'custom',
                                     instruction: 'Private synthetic instruction')
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Synthetic write', slug: 'synthetic_write',
                                    endpoint_url: 'https://example.invalid', http_method: 'POST',
                                    headers_config: [], param_schema: [], response_mapping: {})
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  [true, false].each do |can_edit|
    it "keeps the server warning #{can_edit} in the job, Redis, poll and detail without trusting client input" do
      tool
      unless can_edit
        role = create(:custom_role, account: account, permissions: ['autonomia_view'])
        user.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
      end
      answer = Autonomia::Agents::AnswerResult.new(reply: 'Synthetic response', confidence: 0.9,
                                                   handoff: { should: false, reason: nil }, writes_external: can_edit)
      answerer = instance_double(Autonomia::Agents::Answerer, answer: answer)
      allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('writes_external')).to eq(can_edit)

      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/test",
           params: { message: 'Synthetic question', writes_external: !can_edit }, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      request = response.parsed_body
      expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'writes_external')).to be(false)

      Crm::Ai::InteractiveJob.perform_now(request.fetch('id'))
      expect(Autonomia::Agents::Answerer).to have_received(:new).with(hash_including(pode_editar: can_edit))
      expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test', 'writes_external')).to eq(can_edit)
      redis_request = Crm::Ai::InteractiveRequest.read(request.fetch('id'))
      expect(redis_request.fetch('result').fetch('writes_external')).to eq(can_edit)

      get request.fetch('poll_url'), headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('result').fetch('writes_external')).to eq(can_edit)
      expect(response.parsed_body.to_json).not_to include('Private synthetic instruction', 'headers_config', 'endpoint_url')

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('writes_external')).to eq(can_edit)
      expect(response.parsed_body.fetch('state').fetch('code')).to eq(can_edit ? 'E4' : 'E3')
    end
  end
end
