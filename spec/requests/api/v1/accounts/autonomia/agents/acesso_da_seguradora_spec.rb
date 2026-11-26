require 'rails_helper'

# #3211 (Tarefa 21) — o login do corretor na seguradora do agente contratado, pela API. A conferência é feita na hora
# (o Setup da Universal) e a resposta é só o `payload_publico`: nunca a senha, nunca o login inteiro (R5). O login é
# credencial de integração: só o administrador o grava (CLAUDE.md, funções personalizadas); ver o estado segue com a
# leitura da área de Agentes.
RSpec.describe 'Autonomia agente contratado: acesso à seguradora', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:outra_conta) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agente_sem_funcao) { create(:user, account: account, role: :agent) }
  let(:setup_url) { 'https://api-br.universal-assistance.com/v1/Emissor/Setup' }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:agente) { contratado_em(account) }
  let(:agent_url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}" }
  let(:acesso_url) { "#{agent_url}/acesso_da_seguradora" }
  let(:credenciais) { { login: 'corretor.teste', senha: 's3nha-teste' } }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    [account, outra_conta].each do |conta|
      conta.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas', 'agente_ferramentas_prontas_consultas')
    end
    stub_request(:get, setup_url).to_return(status: 200, body: file_fixture('../universal/setup.json').read)
  end

  def contratado_em(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca })
  end

  def com_funcao(permissoes)
    pessoa = create(:user, account: account, role: :agent)
    pessoa.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    pessoa
  end

  describe 'POST' do
    it 'acesso: POST confere e nunca devolve a senha nem o login (R5)' do
      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('s3nha-teste', 'corretor.teste')
      expect(response.parsed_body).to include('estado' => 'ok', 'login_dica' => 'co•••te')
      expect(response.parsed_body.keys).to match_array(%w[seguradora login_dica estado motivo conferido_em])
      expect(agente.reload.acesso_da_seguradora).to have_attributes(login: 'corretor.teste', senha: 's3nha-teste', estado: 'ok')
    end

    it 'o login e a senha saem filtrados do log do Rails' do
      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(request.filtered_parameters).to include('login' => '[FILTERED]', 'senha' => '[FILTERED]')
      expect(request.filtered_parameters.to_s).not_to include('s3nha-teste', 'corretor.teste')
    end

    it 'login recusado pela seguradora: 200 com o estado recusado, sem a senha, e nada gravado' do
      stub_request(:get, setup_url).to_return(status: 401)

      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('estado' => 'recusado', 'motivo' => 'acesso_recusado', 'login_dica' => nil)
      expect(response.body).not_to include('s3nha-teste')
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end

    it 'seguradora sem resposta (timeout): 200 com o estado nomeado, nunca 5xx, e nada gravado' do
      stub_request(:get, setup_url).to_timeout

      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('estado' => 'nao_conferido', 'motivo' => 'indisponivel', 'login_dica' => nil)
      expect(response.body).not_to include('s3nha-teste')
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end

    # "Nada foi guardado" (a tela): a tentativa errada ao trocar o login não derruba o acesso que já funciona.
    it 'troca recusada depois de um acesso ok: devolve a recusa e o GET segue com o acesso anterior' do
      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json
      stub_request(:get, setup_url).to_return(status: 401)

      post acesso_url, params: { login: 'outro.corretor', senha: 'errada' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('estado' => 'recusado', 'motivo' => 'acesso_recusado')
      expect(agente.reload.acesso_da_seguradora).to have_attributes(login: 'corretor.teste', senha: 's3nha-teste', estado: 'ok')
      get acesso_url, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('estado' => 'ok', 'login_dica' => 'co•••te', 'motivo' => nil)
    end

    it 'login ou senha em branco: 422 sem chamar a seguradora nem gravar' do
      post acesso_url, params: { login: 'corretor.teste', senha: ' ' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'acesso_incompleto', 'campo' => 'senha',
                                              'error' => I18n.t('autonomia.contratados.acesso_incompleto'))
      expect(a_request(:get, setup_url)).not_to have_been_made
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end

    it 'sem a flag do modelo: 422 indisponivel sem chamar a seguradora' do
      account.disable_features!('agente_seguro_viagem_universal')

      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'indisponivel', 'campo' => nil)
      expect(a_request(:get, setup_url)).not_to have_been_made
    end

    it 'agente que não é contratado: 404' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'x')

      url = "/api/v1/accounts/#{account.id}/autonomia/agents/#{comum.id}/acesso_da_seguradora"
      post url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(a_request(:get, setup_url)).not_to have_been_made
    end

    it 'agente de outra conta: 404' do
      outro = contratado_em(outra_conta)

      url = "/api/v1/accounts/#{account.id}/autonomia/agents/#{outro.id}/acesso_da_seguradora"
      post url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end

    it 'agente sem função não grava o login' do
      post acesso_url, params: credenciais, headers: agente_sem_funcao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end

    it 'função que gerencia os agentes também não grava: credencial não se delega por função' do
      post acesso_url, params: credenciais, headers: com_funcao(%w[autonomia_manage]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:get, setup_url)).not_to have_been_made
      expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
    end
  end

  describe 'GET' do
    it 'sem linha: nao_conferido' do
      get acesso_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('estado' => 'nao_conferido')
    end

    it 'com linha: só o payload público, e quem só vê também lê' do
      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      get acesso_url, headers: com_funcao(%w[autonomia_view]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('estado' => 'ok', 'login_dica' => 'co•••te')
      expect(response.body).not_to include('s3nha-teste', 'corretor.teste')
    end

    it 'acesso: GET do agente mostra só a dica' do
      post acesso_url, params: credenciais, headers: admin.create_new_auth_token, as: :json

      get agent_url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('contratado', 'acesso', 'login_dica')).to eq('co•••te')
      expect(response.body).not_to include('senha')
      expect(response.body).not_to include('s3nha-teste', 'corretor.teste')
    end

    it 'agente comum: contratado nulo no GET do agente' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'x')

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{comum.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('contratado' => nil)
    end
  end
end
