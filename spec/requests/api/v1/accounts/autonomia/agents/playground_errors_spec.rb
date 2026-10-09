require 'rails_helper'

RSpec.describe 'Autonomia playground error codes', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente de teste', agent_type: 'custom',
                                     mode: :manual, instruction: 'Atenda as perguntas de teste.')
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  %w[test suggest].each do |action|
    it "returns a stable code when #{action} receives a blank message without queuing AI" do
      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/#{action}",
             params: { message: '   ' }, headers: administrator.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Crm::Ai::InteractiveJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('message_required')
      expect(response.parsed_body['error'].downcase).not_to include('translation missing')
    end
  end
end
