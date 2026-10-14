require 'rails_helper'

# #1366 — pela API, ativar sem onde trabalhar é 422 com a mensagem da regra; "Começar a atender" é escolher o canal
# (POST channels com ativar), que liga o agente junto com o vínculo; desconectar a última caixa para o agente.
RSpec.describe 'Autonomia agent: onde trabalhar', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:headers) { administrator.create_new_auth_token }
  let(:mensagem) { I18n.t('autonomia.agents.sem_onde_trabalhar') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def agente(**attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: 'Livia', agent_type: 'custom', mode: :guided,
                                       status: :paused, enabled: false }.merge(attrs))
  end

  def url(agent, sufixo = '')
    "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}#{sufixo}"
  end

  describe 'PATCH ativar' do
    it 'devolve 422 com a mensagem ao ativar o externo sem caixa, e nada muda' do
      parado = agente

      patch url(parado), params: { agent: { status: 'active', enabled: true } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq(mensagem)
      expect(parado.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'devolve 422 para o both sem caixa' do
      ambos = agente(actuation: :both)

      patch url(ambos), params: { agent: { status: 'active', enabled: true } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'ativa o interno (Copiloto da equipe) sem caixa' do
      interno = agente(actuation: :internal, status: :draft)

      patch url(interno), params: { agent: { status: 'active', enabled: true } }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(interno.reload).to have_attributes(status: 'active', enabled: true)
      expect(response.parsed_body['tem_onde_trabalhar']).to be(true)
    end

    it 'devolve 422 ao tirar o interno ativo sem caixa do painel (vira externo atendendo no vazio)' do
      interno = agente(actuation: :internal, status: :active, enabled: true)

      patch url(interno), params: { agent: { actuation: 'external' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(interno.reload.actuation).to eq('internal')
    end
  end

  describe 'POST criar já atendendo' do
    it 'devolve 422 ao criar o externo ativo, sem caixa, e não grava' do
      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/agents",
             params: { agent: { name: 'Nova', agent_type: 'custom', status: 'active', enabled: true } },
             headers: headers, as: :json
      end.not_to change(Autonomia::Agents::Agent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq(mensagem)
    end

    it 'cria o interno já ativo' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Ana', agent_type: 'custom', actuation: 'internal', status: 'active', enabled: true } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'POST channels com ativar (Começar a atender neste canal)' do
    it 'conecta e liga o agente parado na mesma operação' do
      parado = agente

      post url(parado, '/channels'), params: { inbox_id: inbox.id, ativar: true }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(parado.reload).to have_attributes(status: 'active', enabled: true)
      expect(parado.agent_inboxes.kept.pluck(:inbox_id)).to eq([inbox.id])
      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_active
    end

    it 'sem ativar, segue recusando o agente parado, sem vínculo' do
      parado = agente

      post url(parado, '/channels'), params: { inbox_id: inbox.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parado.reload.agent_inboxes).to be_empty
      expect(parado.status).to eq('paused')
    end

    it 'recusa o interno, mesmo com ativar' do
      interno = agente(actuation: :internal)

      post url(interno, '/channels'), params: { inbox_id: inbox.id, ativar: true }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(interno.reload.status).to eq('paused')
    end

    it 'não conecta caixa de outra conta (isolamento)' do
      parado = agente
      caixa_alheia = create(:inbox, account: create(:account))

      post url(parado, '/channels'), params: { inbox_id: caixa_alheia.id, ativar: true }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(parado.reload).to have_attributes(status: 'paused', enabled: false)
    end
  end

  describe 'agente de outra conta' do
    it 'não ativa nem conecta (404)' do
      alheio = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Alheio', agent_type: 'custom',
                                                status: :paused, enabled: false)

      patch url(alheio), params: { agent: { status: 'active', enabled: true } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      post url(alheio, '/channels'), params: { inbox_id: inbox.id, ativar: true }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(alheio.reload).to have_attributes(status: 'paused', enabled: false)
    end
  end

  describe 'GET (a leitura da tela)' do
    it 'não conta vínculo arquivado como canal, na lista e no detalhe' do
      agente_ativo = agente(status: :active, enabled: true)
      conectado = Autonomia::Agents::Operate::InboxConnector.new(agent: agente_ativo, inbox: inbox).perform(connect: true)
      conectado.agent_inbox.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers, as: :json
      lido = response.parsed_body['payload'].find { |item| item['id'] == agente_ativo.id }
      expect(lido).to include('channels_count' => 0, 'tem_onde_trabalhar' => false)

      get url(agente_ativo), headers: headers, as: :json
      expect(response.parsed_body).to include('channels_count' => 0, 'tem_onde_trabalhar' => false)
    end
  end

  describe 'DELETE channels' do
    it 'para o agente ao tirar a última caixa, e a lista mostra que ele não tem onde trabalhar' do
      atendendo = agente(status: :active, enabled: true)
      Autonomia::Agents::Operate::InboxConnector.new(agent: atendendo, inbox: inbox).perform(connect: true)

      delete url(atendendo, "/channels/#{inbox.id}"), headers: headers, as: :json
      expect(response).to have_http_status(:no_content)

      get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers, as: :json
      lido = response.parsed_body['payload'].find { |item| item['id'] == atendendo.id }
      expect(lido).to include('status' => 'paused', 'enabled' => false, 'channels_count' => 0, 'tem_onde_trabalhar' => false)
    end
  end
end
