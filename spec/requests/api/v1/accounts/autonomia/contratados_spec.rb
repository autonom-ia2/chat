require 'rails_helper'

# #3211 (Tarefa 21) — o catálogo dos agentes contratados e o "Contratar", pela API. O catálogo devolve só as chaves (os
# textos são da tela) e fica vazio sem a flag. A recusa é 422 com o código e o campo que a tela destaca (R14).
RSpec.describe 'Autonomia agentes contratados: catálogo e contratar', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agente_sem_funcao) { create(:user, account: account, role: :agent) }
  let(:catalogo_url) { "/api/v1/accounts/#{account.id}/autonomia/contratados" }
  let(:contratar_url) { "#{catalogo_url}/seguro_viagem_universal" }
  let(:tres_campos) { { nome_agente: 'Bia', nome_corretora: 'Corretora Exemplo', sobre_corretora: 'Corretora de seguros desde 2010.' } }
  let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService, embed_batch: []) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas', 'agente_ferramentas_prontas_consultas')
    # Contratar exige a chave de IA da própria conta; a de mentira não passa pelo provedor.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
  end

  def com_funcao(permissoes)
    pessoa = create(:user, account: account, role: :agent)
    pessoa.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    pessoa
  end

  describe 'GET contratados' do
    it 'lista só as chaves dos modelos disponíveis' do
      get catalogo_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('modelos' => ['seguro_viagem_universal'], 'falta_chave_de_ia' => false)
    end

    it 'vazio sem a flag do modelo' do
      account.disable_features!('agente_seguro_viagem_universal')

      get catalogo_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('modelos' => [], 'falta_chave_de_ia' => false)
    end

    it 'conta que não é corretora de seguros não recebe o modelo (#3269)' do
      Autonomia::Agents::Nicho.atribuir(account, nicho: Autonomia::Agents::Nicho::GERAL, perfil: nil)
      account.save!

      get catalogo_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('modelos' => [], 'falta_chave_de_ia' => false)
    end

    it 'agente sem função não lê o catálogo' do
      get catalogo_url, headers: agente_sem_funcao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST contratados/:modelo' do
    it 'contrata e responde o agente com a marca pública' do
      post contratar_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['contratado']).to eq(
        'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
        'sobre_corretora' => 'Corretora de seguros desde 2010.', 'acesso' => nil
      )
      expect(response.parsed_body).to include('name' => 'Bia', 'status' => 'draft')
      expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).created_by).to eq(admin)
    end

    it 'agente de quem só vê não contrata' do
      post contratar_url, params: tres_campos, headers: agente_sem_funcao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'função só de ver os agentes não contrata' do
      post contratar_url, params: tres_campos, headers: com_funcao(%w[autonomia_view]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'função que gerencia os agentes contrata' do
      post contratar_url, params: tres_campos, headers: com_funcao(%w[autonomia_manage]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'recusa com o campo que a tela destaca (R14)' do
      post contratar_url, params: tres_campos.merge(nome_corretora: '$nomeAgente'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.slice('code', 'campo')).to eq('code' => 'marcador', 'campo' => 'nome_corretora')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.contratados.recusa.marcador'))
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'nome do agente em branco: o campo é o motivo e o campo, com o texto do tamanho' do
      post contratar_url, params: tres_campos.merge(nome_agente: '  '), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.slice('code', 'campo')).to eq('code' => 'nome_agente', 'campo' => 'nome_agente')
      expect(response.parsed_body['error']).to include('120')
      expect(response.parsed_body['error']).not_to include('Translation missing')
    end

    it 'sem a flag: indisponivel, sem campo, nada criado' do
      account.disable_features!('agente_seguro_viagem_universal')

      post contratar_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'indisponivel', 'campo' => nil,
                                              'error' => I18n.t('autonomia.contratados.recusa.indisponivel'))
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'conta que não é corretora de seguros: indisponivel, nada criado (#3269)' do
      marcar_corretora!(account, perfil: 'seguradora')

      post contratar_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'indisponivel', 'campo' => nil)
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'conta sem a própria chave de IA: o catálogo mostra o modelo, e contratar diz o que falta' do
      Integrations::Hook.where(account_id: account.id, app_id: 'crm_kanban_ai').delete_all

      get catalogo_url, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('modelos' => ['seguro_viagem_universal'], 'falta_chave_de_ia' => true)

      post contratar_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'sem_chave_de_ia', 'campo' => nil,
                                              'error' => I18n.t('autonomia.contratados.recusa.sem_chave_de_ia'))
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'modelo fora do catálogo: indisponivel' do
      post "#{catalogo_url}/outro_modelo", params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('indisponivel')
    end

    it 'campo fora dos três não entra no agente' do
      post contratar_url, params: tres_campos.merge(agent_type: 'custom', instruction: 'forjada', config: { system_key: 'x' }),
                          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      agente = Autonomia::Agents::Agent.find(response.parsed_body['id'])
      expect(agente.agent_type).to eq('sdr')
      expect(agente.instruction).not_to eq('forjada')
      expect(agente.config).not_to include('system_key')
    end
  end
end
