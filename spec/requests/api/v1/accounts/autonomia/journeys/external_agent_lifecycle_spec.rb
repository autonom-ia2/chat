require 'rails_helper'

# Jornada "caminhos tristes" do agente EXTERNO (atende clientes) via API de agentes:
# ativação sem instrução, transições de status/modo, mudança de atuação com canal
# conectado, deleção com vínculo ativo e limites de autorização/flags. Documenta o
# comportamento ATUAL do código (specs de regressão, não de intenção futura).
RSpec.describe 'Autonomia journeys - external agent lifecycle', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_external_agent(attrs = {})
    Autonomia::Agents::Agent.create!(
      { account: account, name: 'Agente Externo', agent_type: 'support', mode: :guided,
        status: :draft, enabled: false, actuation: :external }.merge(attrs)
    )
  end

  def connect_inbox(agent, inbox)
    result = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true)
    raise "setup failed: #{result.error}" unless result.success?

    result.agent_inbox
  end

  describe 'activation without instruction' do
    it 'activates an external agent even when it has no instruction' do
      # Arrange — agente externo recém-criado, sem instrução nenhuma.
      agent = create_external_agent(instruction: nil)

      # Act
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { status: 'active', enabled: true } },
            headers: administrator.create_new_auth_token,
            as: :json

      # Assert — comportamento ATUAL: nenhuma validação exige instrução na ativação;
      # o agente fica ativo/ligado mesmo "vazio".
      # TODO(onda-N): se o produto decidir exigir instrução para ativar agente externo,
      # este spec deve passar a assertar 422 (hoje a API aceita ativar sem instrução).
      expect(response).to have_http_status(:success)
      expect(agent.reload).to have_attributes(status: 'active', enabled: true, instruction: nil)
    end
  end

  describe 'status transitions' do
    it 'keeps the inbox link intact across active -> paused -> active' do
      # Arrange — agente ativo com canal conectado.
      agent = create_external_agent(status: :active, enabled: true, instruction: 'Atenda bem.')
      inbox = create(:inbox, account: account)
      agent_inbox = connect_inbox(agent, inbox)

      # Act — pausa e reativa pela API.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { status: 'paused' } },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(agent.reload.status).to eq('paused')

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { status: 'active' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — o vínculo agente↔inbox sobrevive às transições (mesmo registro).
      expect(response).to have_http_status(:success)
      expect(agent.reload.status).to eq('active')
      expect(Autonomia::Agents::AgentInbox.find_by(id: agent_inbox.id)).to be_present
      expect(agent.agent_inboxes.count).to eq(1)
    end
  end

  describe 'mode transitions' do
    it 'discards the builder-generated instruction when switching guided -> manual without a new one' do
      # Arrange — instrução gerada pelo Construtor (IP oculto em modo guiado).
      agent = create_external_agent(mode: :guided, instruction: 'INSTRUCAO GERADA PELO CONSTRUTOR')

      # Act — troca para manual SEM mandar instrução própria.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { mode: 'manual' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — a instrução gerada é descartada (nunca vaza em modo manual) e o
      # backend aplica o andaime manual oculto.
      expect(response).to have_http_status(:success)
      expect(agent.reload.instruction).to be_nil
      expect(agent.mode).to eq('manual')
      expect(agent.scaffold).to eq(Api::V1::Accounts::Autonomia::AgentsController::MANUAL_SCAFFOLD)
    end

    it 'ignores the instruction param when switching manual -> guided' do
      # Arrange — agente manual com instrução do próprio usuário.
      agent = create_external_agent(mode: :manual, instruction: 'MINHA INSTRUCAO MANUAL',
                                    scaffold: Api::V1::Accounts::Autonomia::AgentsController::MANUAL_SCAFFOLD)

      # Act — volta para guiado tentando injetar uma instrução via params.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { mode: 'guided', instruction: 'TENTATIVA DE INJECAO' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — comportamento ATUAL: em modo guiado `instruction` não é permitida
      # nos params (só o Construtor escreve); a instrução manual anterior permanece.
      expect(response).to have_http_status(:success)
      expect(agent.reload.mode).to eq('guided')
      expect(agent.instruction).to eq('MINHA INSTRUCAO MANUAL')
    end
  end

  describe 'actuation change with connected channel' do
    it 'rejects switching to internal while a channel is still connected' do
      # Arrange — agente externo ativo com canal conectado.
      agent = create_external_agent(status: :active, enabled: true, instruction: 'Atenda bem.')
      inbox = create(:inbox, account: account)
      connect_inbox(agent, inbox)

      # Act
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { actuation: 'internal' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — 422 e nada persiste (interno nunca atende cliente; vínculo ficaria órfão).
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
      expect(agent.reload.actuation).to eq('external')
      expect(agent.agent_inboxes.count).to eq(1)
    end
  end

  describe 'deletion' do
    it 'destroys an active agent and cleans up the inbox link plus the mirror bot' do
      # Arrange — agente ativo conectado a um inbox (AgentBot espelho + AgentBotInbox criados).
      agent = create_external_agent(status: :active, enabled: true, instruction: 'Atenda bem.')
      inbox = create(:inbox, account: account)
      agent_inbox = connect_inbox(agent, inbox)
      mirror_bot_id = agent_inbox.agent_bot_id

      # Act
      delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
             headers: administrator.create_new_auth_token, as: :json

      # Assert — o vínculo cai (dependent: :destroy) e o after_destroy limpa o espelho:
      # AgentBotInbox e o AgentBot espelho (outgoing_url NULL) são removidos juntos.
      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::Agent.find_by(id: agent.id)).to be_nil
      expect(Autonomia::Agents::AgentInbox.find_by(id: agent_inbox.id)).to be_nil
      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_nil
      expect(AgentBot.find_by(id: mirror_bot_id)).to be_nil
    end

    it 'destroys a draft agent with no links' do
      # Arrange
      agent = create_external_agent

      # Act
      delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
             headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::Agent.find_by(id: agent.id)).to be_nil
    end
  end

  describe 'config updates' do
    it 'preserves with_knowledge and reviewer-computed keys when updating config via API' do
      # Arrange — with_knowledge/topic_map são chaves COMPUTADAS (PROTECTED_CONFIG_KEYS):
      # o usuário não as define pela API e um update de config não pode apagá-las.
      agent = create_external_agent(
        config: { 'with_knowledge' => false, 'topic_map' => [{ 'topic' => 'frete' }], 'temperature' => 0.2 }
      )

      # Act — update mandando config nova (inclusive tentando sobrescrever with_knowledge).
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { config: { temperature: 0.7, with_knowledge: true } } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — merge preserva as protegidas; só a chave livre (temperature) muda.
      expect(response).to have_http_status(:success)
      agent.reload
      expect(agent.config['with_knowledge']).to be(false)
      expect(agent.config['topic_map']).to eq([{ 'topic' => 'frete' }])
      expect(agent.config['temperature']).to eq(0.7)
    end

    # #380 — as escolhas da corretora (`agente_de_cotacao`) são lidas a cada turno pelo Agente de
    # Cotação e só o Builder as escreve, sempre as quatro. Uma escrita parcial pela API pararia o
    # agente com `EscolhasIncompletas`; uma completa trocaria o nome dele por fora do fluxo.
    it 'preserves the quote agent choices when updating config via API' do
      # Arrange
      chave = Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA
      escolhas = { 'nome_agente' => 'Lia', 'nome_corretora' => 'Sena', 'horario' => 'seg a sex', 'comportamento' => 'consultivo' }
      agent = create_external_agent(agent_type: 'insurance_quote', config: { chave => escolhas })

      # Act — tenta trocar só o nome, por fora do Builder.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { config: { chave => { 'nome_agente' => 'Outra' }, 'temperature' => 0.7 } } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — as escolhas ficam como o Builder gravou; a chave livre muda.
      expect(response).to have_http_status(:success)
      agent.reload
      expect(agent.config[chave]).to eq(escolhas)
      expect(agent.config['temperature']).to eq(0.7)
    end
  end

  # #380 (rodada de correção) — a instrução do Agente de Cotação é mantida pela Autonom.ia: o prompt é o
  # arquivo do deploy com as escolhas da corretora, e a coluna é retrato do nascimento. O hub abre a Lia
  # na mesma tela dos outros agentes (PanelTune), com o modo avançado; antes desta guarda o PATCH era
  # aceito, exibido e ignorado em silêncio. Agora recusa com 422 e diz o porquê. O save comum do
  # PanelTune (que sempre carimba `mode: 'guided'`) continua passando.
  describe 'quote agent instruction is maintained by Autonom.ia' do
    let(:mensagem) { I18n.t('autonomia.agents.instrucao_mantida') }
    let(:lia) do
      Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call
    end

    def prompt_de(agente)
      Autonomia::Agents::PromptBuilder.new(agent: agente, query: 'oi').instructions
    end

    it 'refuses the advanced-mode edit with a clear message and keeps the deploy instruction' do
      # Arrange
      nascimento = lia.instruction

      # Act — o admin liga o modo avançado no hub e salva a instrução dele.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}",
            params: { agent: { mode: 'manual', instruction: 'Minha instrução própria da corretora.' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert — 422 com a mensagem; nada gravado; o prompt segue sendo o arquivo com as escolhas.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(mensagem)
      lia.reload
      expect(lia.mode).to eq('guided')
      expect(lia.instruction).to eq(nascimento)
      expect(lia.instruction_versions).not_to exist
      expect(prompt_de(lia)).to include('Você é Lia, e atende pela corretora Sena.')
      expect(prompt_de(lia)).not_to include('Minha instrução própria')
    end

    it 'refuses an instruction sent without switching mode, instead of ignoring it in silence' do
      # Act
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}",
            params: { agent: { instruction: 'Minha instrução própria da corretora.' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(mensagem)
    end

    it 'still accepts the ordinary PanelTune save, which always stamps mode guided' do
      # Act — o payload do PanelTune: campos simples + `mode: 'guided'` + config das virtuais.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}",
            params: { agent: { greeting: 'Olá! Sou a Lia.', tone: 'cordial', mode: 'guided',
                               config: { handoff_strategy: 'none', confidence_threshold: 0.5 } } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:success)
      lia.reload
      expect(lia.greeting).to eq('Olá! Sou a Lia.')
      expect(lia.config['handoff_strategy']).to eq('none')
      expect(lia.config[Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA]).to include('nome_agente' => 'Lia')
    end

    # Pela API genérica nasceria uma Lia sem escolhas, lendo uma coluna que ninguém mantém. O agente
    # de cotação nasce só pela aba Cotação (`Insurance::QuoteAgentController#create`).
    it 'refuses to create a quote agent through the generic agents API' do
      # Act
      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/agents",
             params: { agent: { name: 'Lia', agent_type: 'insurance_quote' } },
             headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Autonomia::Agents::Agent, :count)

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(mensagem)
    end
  end

  describe 'invalid input' do
    it 'returns 422 for an unknown actuation enum value instead of a 500' do
      # Arrange
      agent = create_external_agent

      # Act — valor fora do enum levantaria ArgumentError; o BaseController converte em 422.
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { actuation: 'sideways' } },
            headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('is not a valid')
      expect(agent.reload.actuation).to eq('external')
    end

    it 'returns 422 when creating an agent with an unknown agent_type' do
      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Tipo Invalido', agent_type: 'ninja' } },
           headers: administrator.create_new_auth_token, as: :json

      # Assert — validação de inclusão do model vira RecordInvalid -> 422.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Autonomia::Agents::Agent.where(account: account).count).to eq(0)
    end
  end

  describe 'authorization and gates' do
    it 'blocks non-admin users from creating or editing agents' do
      # Arrange
      agent = create_external_agent

      # Act / Assert — criação
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Nao Deveria', agent_type: 'support' } },
           headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      # Act / Assert — edição
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { status: 'active' } },
            headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(agent.reload.status).to eq('draft')
    end

    it 'hides the whole agents API when the account flag is off even with the ENV master on' do
      # Arrange — conta SEM a marca interna (ENV master ligada não basta).
      unflagged_account = create(:account)
      unflagged_admin = create(:user, account: unflagged_account, role: :administrator)

      # Act
      get "/api/v1/accounts/#{unflagged_account.id}/autonomia/agents",
          headers: unflagged_admin.create_new_auth_token, as: :json

      # Assert — porta única: 404, a área inteira some.
      expect(response).to have_http_status(:not_found)
    end
  end
end
