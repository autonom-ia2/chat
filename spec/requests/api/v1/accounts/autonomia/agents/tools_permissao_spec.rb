require 'rails_helper'

# #1430 — quem gerencia as ferramentas HTTP do agente. Com a flag `agente_ferramentas_delegadas` ligada na conta: o
# administrador e quem tem a chave `autonomia_tools_manage` (protegida, implica `autonomia_view`). Desligada: só a equipe
# da plataforma, como antes. Quem só vê ou edita agentes, sem a chave, recebe recusa em tudo de ferramentas e vê só a
# contagem das ligadas. O valor de um cabeçalho secreto nunca volta, para ninguém.
RSpec.describe 'Autonomia agent tools permission', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom') }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/tools" }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:super_admin) { create(:super_admin) }
  let(:segredo) { 'chave-da-loja-987' }
  let(:corpo) do
    { tool: { name: 'Estoque', endpoint_url: 'https://api.loja.test/estoque', http_method: 'GET',
              headers_config: [{ key: 'x-api-key', value: segredo, secret: true }] } }
  end
  let!(:ferramenta) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Frete', endpoint_url: 'https://api.loja.test/frete',
                                    headers_config: [{ key: 'x-api-key', value: segredo, secret: true }])
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def com_funcao(permissoes, conta: account)
    pessoa = create(:user, account: conta, role: :agent)
    pessoa.account_users.find_by(account: conta).update!(custom_role: create(:custom_role, account: conta, permissions: permissoes))
    pessoa
  end

  def ligar_flag
    account.enable_features!('agente_ferramentas_delegadas')
  end

  context 'with the flag off' do
    it 'keeps tools with the platform team only' do
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      create(:account_user, account: account, user: super_admin, role: :administrator)
      get base, headers: super_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'refuses the tools key holder too' do
      get base, headers: com_funcao(%w[autonomia_tools_manage]).create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with the flag on' do
    before { ligar_flag }

    # #1430: a tela manda o nome de gente de cada informação ("CEP"), e ele volta na leitura.
    it 'keeps the label of each piece of information' do
      com_rotulo = corpo.deep_merge(tool: { endpoint_url: 'https://api.loja.test/cep/{{cep}}',
                                            param_schema: [{ name: 'cep', label: 'CEP', type: 'string', required: true }] })
      post base, params: com_rotulo, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['param_schema'].first).to include('name' => 'cep', 'label' => 'CEP')
    end

    it 'lets the administrator list and create tools' do
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      post base, params: corpo, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'lets the tools key holder create, edit, test and delete, never reading the secret back' do
      pessoa = com_funcao(%w[autonomia_tools_manage])

      post base, params: corpo, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      expect(response.body).not_to include(segredo)
      id = response.parsed_body['id']

      get base, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(segredo)

      patch "#{base}/#{id}", params: { tool: { description: 'Consulta o estoque' } }, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(segredo)

      delete "#{base}/#{id}", headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'refuses whoever edits agents but has no tools key' do
      pessoa = com_funcao(%w[autonomia_manage])

      get base, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      post base, params: corpo, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/#{ferramenta.id}/test", headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses whoever only sees agents, and a plain agent' do
      [com_funcao(%w[autonomia_view]), create(:user, account: account, role: :agent)].each do |pessoa|
        get base, headers: pessoa.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'shows only the count of enabled tools to whoever sees the agent' do
      Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Desligada', endpoint_url: 'https://api.loja.test/x',
                                      enabled: false)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: com_funcao(%w[autonomia_view]).create_new_auth_token,
                                                                         as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ferramentas_ligadas']).to eq(1)
      expect(response.body).not_to include('api.loja.test')
      expect(response.body).not_to include(segredo)
    end

    it 'refuses a tool on the quote agent (Lia)' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote')

      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/tools", params: corpo, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(lia.tools.count).to eq(0)
    end

    # #1430 (revisão): a Lia fica fora em TODA ação para a conta; a equipe da plataforma continua cuidando dela.
    context 'with the quote agent (Lia)' do
      let(:lia) { Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote') }
      let(:lia_base) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/tools" }
      let!(:da_lia) do
        Autonomia::Agents::Tool.create!(account: account, agent: lia, name: 'Cotar', endpoint_url: 'https://api.loja.test/cotar',
                                        headers_config: [{ key: 'x-api-key', value: segredo, secret: true }])
      end

      it 'refuses list, change, test and delete to the key holder' do
        token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token

        get lia_base, headers: token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        patch "#{lia_base}/#{da_lia.id}", params: { tool: { endpoint_url: 'https://outro.test/x' } }, headers: token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        post "#{lia_base}/#{da_lia.id}/test", headers: token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        delete "#{lia_base}/#{da_lia.id}", headers: token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(da_lia.reload.endpoint_url).to eq('https://api.loja.test/cotar')
      end

      it 'keeps the platform team managing her tools' do
        create(:account_user, account: account, user: super_admin, role: :administrator)

        post lia_base, params: corpo, headers: super_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
      end
    end

    # #1430 (revisão adversarial): o segredo guardado não segue o endereço para outro site.
    it 'refuses moving a tool to another site while keeping the stored secret' do
      token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token

      patch "#{base}/#{ferramenta.id}", params: { tool: { endpoint_url: 'https://coletor.test/x' } }, headers: token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['campos']).to eq(['headers_config'])
      expect(ferramenta.reload.endpoint_url).to eq('https://api.loja.test/frete')
    end

    it 'refuses changing the path on the same site while keeping the stored secret' do
      token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token

      patch "#{base}/#{ferramenta.id}", params: { tool: { endpoint_url: 'https://api.loja.test/clientes' } }, headers: token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['campos']).to eq(['headers_config'])
      expect(ferramenta.reload.endpoint_url).to eq('https://api.loja.test/frete')
    end

    it 'accepts a new path when the same key is typed again' do
      token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token
      tool = { endpoint_url: 'https://api.loja.test/clientes', headers_config: [{ key: 'x-api-key', value: segredo, secret: true }] }

      patch "#{base}/#{ferramenta.id}", params: { tool: tool }, headers: token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(segredo)
      expect(ferramenta.reload.endpoint_url).to eq('https://api.loja.test/clientes')
    end

    it 'refuses a method override header while keeping the stored secret' do
      token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token
      cabecalhos = [{ key: 'x-api-key', value: Autonomia::Agents::Tool.masked_header_value, secret: true },
                    { key: 'X-HTTP-Method-Override', value: 'DELETE', secret: false }]

      patch "#{base}/#{ferramenta.id}", params: { tool: { headers_config: cabecalhos } }, headers: token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ferramenta.reload.headers_config.size).to eq(1)
    end

    it 'refuses a typed header next to the masked one with the same name' do
      token = com_funcao(%w[autonomia_tools_manage]).create_new_auth_token
      cabecalhos = [{ key: 'x-api-key', value: 'lixo', secret: true },
                    { key: 'x-api-key', value: Autonomia::Agents::Tool.masked_header_value, secret: true }]

      patch "#{base}/#{ferramenta.id}", params: { tool: { endpoint_url: 'https://coletor.test/x', headers_config: cabecalhos } },
                                        headers: token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include(segredo)
      expect(ferramenta.reload.endpoint_url).to eq('https://api.loja.test/frete')
    end

    it 'lets the key holder test a tool without the secret coming back' do
      executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"ok":true}')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(executor)

      post "#{base}/#{ferramenta.id}/test", headers: com_funcao(%w[autonomia_tools_manage]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(segredo)
      # Tester do #1430: um site que repete os cabeçalhos devolveria a chave na resposta 2xx do Testar.
      expect(Autonomia::Agents::Tools::HttpExecutor).to have_received(:new).with(hash_including(higienizar: true))
    end

    it 'does not reach the tools of another account' do
      outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      outra.enable_features!('agente_ferramentas_delegadas')
      pessoa = com_funcao(%w[autonomia_tools_manage], conta: outra)

      get "/api/v1/accounts/#{outra.id}/autonomia/agents/#{agent.id}/tools", headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      get base, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
