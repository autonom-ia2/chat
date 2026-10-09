require 'rails_helper'

RSpec.describe 'Autonomia agent copilot availability', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:available) { false }
  let(:availability_result) do
    Struct.new(:available, :reasons, :can_choose_internal).new(
      available, available ? [] : [:crm], available
    )
  end
  let(:availability_service) do
    instance_double(Autonomia::Agents::CopilotAvailability, call: availability_result)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::CopilotAvailability).to receive(:new).and_return(availability_service)
  end

  def create_agent(attrs = {})
    Autonomia::Agents::Agent.create!(
      { account: account, name: 'Agente de teste', agent_type: 'custom', mode: :guided,
        status: :draft, enabled: false, actuation: :external }.merge(attrs)
    )
  end

  def create_agent_request(actuation:, user: administrator, name: 'Novo agente')
    post "/api/v1/accounts/#{account.id}/autonomia/agents",
         params: { agent: { name: name, agent_type: 'custom', mode: 'guided',
                            status: 'draft', enabled: false, actuation: actuation } },
         headers: user.create_new_auth_token,
         as: :json
  end

  [1, 2].each do |actuation|
    it "rejects numeric actuation #{actuation} on create before any write" do
      before_agents = Autonomia::Agents::Agent.count
      before_bots = AgentBot.count
      before_links = Autonomia::Agents::AgentInbox.count

      create_agent_request(actuation: actuation)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'invalid_enum')
      expect(Autonomia::Agents::Agent.count).to eq(before_agents)
      expect(AgentBot.count).to eq(before_bots)
      expect(Autonomia::Agents::AgentInbox.count).to eq(before_links)
    end

    it "rejects numeric actuation #{actuation} on update without a partial name write" do
      agent = create_agent(name: 'Nome original')
      before_bots = AgentBot.count
      before_links = Autonomia::Agents::AgentInbox.count

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { name: 'Nome indevido', actuation: actuation } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'invalid_enum')
      expect(agent.reload).to have_attributes(name: 'Nome original', actuation: 'external')
      expect(AgentBot.count).to eq(before_bots)
      expect(Autonomia::Agents::AgentInbox.count).to eq(before_links)
    end
  end

  describe 'create' do
    %w[internal both].each do |actuation|
      it "rejects #{actuation} before writing anything when the copilot is unavailable" do
        before_agents = Autonomia::Agents::Agent.count
        before_bots = AgentBot.count
        before_links = Autonomia::Agents::AgentInbox.count

        create_agent_request(actuation: actuation)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('code' => 'copilot_unavailable')
        expect(Autonomia::Agents::Agent.count).to eq(before_agents)
        expect(AgentBot.count).to eq(before_bots)
        expect(Autonomia::Agents::AgentInbox.count).to eq(before_links)
      end
    end

    it 'allows an internal agent when the copilot is available' do
      allow(availability_result).to receive(:available).and_return(true)
      allow(availability_result).to receive(:can_choose_internal).and_return(true)

      expect { create_agent_request(actuation: 'internal') }
        .to change(Autonomia::Agents::Agent, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::Agent.order(:id).last.actuation).to eq('internal')
    end

    it 'returns 401 to a person without autonomia_manage' do
      before_agents = Autonomia::Agents::Agent.count

      create_agent_request(actuation: 'internal', user: agent_user)

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::Agent.count).to eq(before_agents)
    end
  end

  describe 'update' do
    it 'rejects an internal transition before a partial name write when unavailable' do
      agent = create_agent(name: 'Nome original')
      before_bots = AgentBot.count
      before_links = Autonomia::Agents::AgentInbox.count

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { name: 'Nome alterado', actuation: 'internal' } },
            headers: administrator.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'copilot_unavailable')
      expect(agent.reload).to have_attributes(name: 'Nome original', actuation: 'external')
      expect(AgentBot.count).to eq(before_bots)
      expect(Autonomia::Agents::AgentInbox.count).to eq(before_links)
    end

    it 'allows changing actuation to both when the copilot is available' do
      allow(availability_result).to receive(:available).and_return(true)
      allow(availability_result).to receive(:can_choose_internal).and_return(true)
      agent = create_agent

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { name: 'Nome novo', actuation: 'both' } },
            headers: administrator.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload).to have_attributes(name: 'Nome novo', actuation: 'both')
    end
  end
end
