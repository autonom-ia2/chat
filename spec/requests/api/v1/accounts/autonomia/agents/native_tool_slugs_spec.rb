require 'rails_helper'

# #1211 — a API de agentes aceitava `config.native_tool_slugs` de qualquer fluxo: quem edita um agente
# comum ligava nele as ferramentas do Guia da Plataforma. A lista permitida é a do fluxo do agente
# (`Tools::Registry.permitidas_para`), e o que está fora dela é recusado com o slug na resposta.
RSpec.describe 'Autonomia agent native tool slugs', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', instruction: 'Atenda.',
                                     config: { 'handoff_strategy' => 'none' })
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/agents" }
  let(:slug_do_guia) { Autonomia::Agents::Tools::Native::GuiaPagina.slug }
  let(:slug_de_atendimento) { Autonomia::Agents::Tools::Native::InsuranceGeneralConditions.slug }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/autonomia/agents/:id' do
    it 'refuses a Platform Guide tool on an account agent and stores nothing' do
      patch "#{base_url}/#{agent.id}",
            params: { agent: { name: 'Outro nome', config: { native_tool_slugs: [slug_de_atendimento, slug_do_guia] } } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'native_tool_not_allowed', 'slugs' => [slug_do_guia])
      expect(agent.reload.config).to eq('handoff_strategy' => 'none')
      expect(agent.name).to eq('Ana')
    end

    it 'refuses every tool of the Platform Guide, one by one' do
      Autonomia::Guide::Seed::FERRAMENTAS.each do |slug|
        patch "#{base_url}/#{agent.id}", params: { agent: { config: { native_tool_slugs: [slug] } } },
                                         headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity), "aceitou #{slug}"
      end
      expect(agent.reload.native_tool_slugs).to be_nil
    end

    it 'refuses a slug that is not in the catalogue' do
      patch "#{base_url}/#{agent.id}", params: { agent: { config: { native_tool_slugs: ['ferramenta_que_nao_existe'] } } },
                                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['slugs']).to eq(['ferramenta_que_nao_existe'])
      expect(agent.reload.native_tool_slugs).to be_nil
    end

    it 'refuses a value that is not a list of slugs' do
      patch "#{base_url}/#{agent.id}", params: { agent: { config: { native_tool_slugs: { '0' => slug_do_guia } } } },
                                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent.reload.native_tool_slugs).to be_nil
    end

    it 'keeps accepting a tool of the agent own flow, merged over the stored config' do
      patch "#{base_url}/#{agent.id}", params: { agent: { config: { native_tool_slugs: [slug_de_atendimento] } } },
                                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload.config).to eq('handoff_strategy' => 'none', 'native_tool_slugs' => [slug_de_atendimento])
    end

    it 'keeps accepting an empty list, which turns every native tool off' do
      agent.update!(config: agent.config.merge('native_tool_slugs' => [slug_de_atendimento]))

      patch "#{base_url}/#{agent.id}", params: { agent: { config: { native_tool_slugs: [] } } },
                                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload.native_tool_slugs).to eq([])
    end

    it 'does not touch a PATCH that says nothing about native tools' do
      patch "#{base_url}/#{agent.id}", params: { agent: { config: { response_window: 'business_hours' } } },
                                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload.config).to eq('handoff_strategy' => 'none', 'response_window' => 'business_hours')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/autonomia/agents' do
    it 'refuses a Platform Guide tool and creates no agent' do
      expect do
        post base_url, params: { agent: { name: 'Novo', agent_type: 'custom', config: { native_tool_slugs: [slug_do_guia] } } },
                       headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Autonomia::Agents::Agent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'native_tool_not_allowed', 'slugs' => [slug_do_guia])
    end

    it 'keeps accepting a tool of the agent own flow' do
      post base_url, params: { agent: { name: 'Novo', agent_type: 'custom', config: { native_tool_slugs: [slug_de_atendimento] } } },
                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).native_tool_slugs).to eq([slug_de_atendimento])
    end
  end
end
