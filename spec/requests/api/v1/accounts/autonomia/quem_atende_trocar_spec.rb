require 'rails_helper'

# chat#1648 — "Quem atende primeiro" na aba "Agente de IA" da caixa: a troca completa (PUT quem_atende). Tira quem
# atende hoje pelo caminho certo (InboxConnector para agente da plataforma, AgentBotInbox para agente de outro sistema) e
# põe o novo, numa transação. As áreas da caixa ficam (#1621).
RSpec.describe 'Autonomia quem_atende: trocar', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_agente_ia_por_caixa' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{inbox.id}/quem_atende" }
  let(:outro_sistema) { create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def porta!(agent, caixa = inbox)
    resultado = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
    expect(resultado).to be_success
    resultado.agent_inbox
  end

  def area!(agent)
    espelho = create(:agent_bot, account: account, name: agent.name, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: espelho, papel: 'area')
  end

  def trocar(user: admin, **params)
    put url, params: params, headers: user.create_new_auth_token, as: :json
  end

  def porta_da_caixa
    Autonomia::Agents::AgentInbox.kept.porta.find_by(inbox_id: inbox.id)
  end

  def robos_da_caixa
    AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)
  end

  def pendente!
    create(:conversation, account: account, inbox: inbox, status: :pending)
  end

  describe 'porta → outra porta' do
    let(:sofia) { agente('Sofia') }
    let(:bia) { agente('Bia') }
    let(:leo) { agente('Leo', status: :paused, enabled: false) }

    before do
      porta!(sofia)
      area!(bia)
    end

    it 'connects the new agent as the porta and turns it on' do
      trocar(agent_id: leo.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa.autonomia_agent_id).to eq(leo.id)
      expect(robos_da_caixa).to eq([porta_da_caixa.agent_bot_id])
      expect(leo.reload).to have_attributes(status: 'active', enabled: true)
      expect(response.parsed_body['primeiro']).to eq('tipo' => 'plataforma', 'id' => leo.id, 'name' => 'Leo')
    end

    it 'disconnects the old agent (it stops without an inbox), hands its conversations to the team and keeps the team agents' do
      conversa = pendente!

      trocar(agent_id: leo.id)

      expect(sofia.reload).to have_attributes(status: 'paused', enabled: false)
      expect(Autonomia::Agents::AgentInbox.kept.area.where(inbox_id: inbox.id).pluck(:autonomia_agent_id)).to eq([bia.id])
      expect(conversa.reload.status).to eq('open')
    end
  end

  describe 'porta → outro sistema' do
    it 'takes the platform agent out and plugs the agent from another system' do
      sofia = agente('Sofia')
      porta!(sofia)
      conversa = pendente!

      trocar(agent_bot_id: outro_sistema.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa).to be_nil
      expect(robos_da_caixa).to eq([outro_sistema.id])
      expect(conversa.reload.status).to eq('open')
      expect(response.parsed_body['primeiro']).to eq('tipo' => 'webhook', 'id' => outro_sistema.id, 'name' => 'Automação')
    end

    # Decisão do Rodrigo de 15/10 (opção B): as áreas ficam e continuam donas das conversas delas.
    it 'keeps the team agents and the conversations they hold' do
      porta!(agente('Sofia'))
      area = area!(agente('Bia'))
      da_area = create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(ai_assignee: area.agent_bot, status: :open) }

      trocar(agent_bot_id: outro_sistema.id)

      expect(response).to have_http_status(:ok)
      expect(robos_da_caixa).to eq([outro_sistema.id])
      expect(area.reload).to have_attributes(deleted_at: nil, papel: 'area')
      expect(da_area.reload).to have_attributes(status: 'open', assignee_agent_bot_id: area.agent_bot_id)
      expect(response.parsed_body['agentes'].pluck('name', 'papel')).to eq([%w[Automação porta], %w[Bia area]])
    end
  end

  describe 'outro sistema → porta' do
    it 'removes the agent from another system and connects the platform agent' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)
      conversa = pendente!
      leo = agente('Leo', status: :paused, enabled: false)

      trocar(agent_id: leo.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa.autonomia_agent_id).to eq(leo.id)
      expect(robos_da_caixa).to eq([porta_da_caixa.agent_bot_id])
      expect(conversa.reload.status).to eq('open')
      expect(outro_sistema.reload).to be_persisted
    end

    it 'swaps one agent from another system for another' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)
      segundo = create(:agent_bot, account: account, name: 'Parceiro', outgoing_url: 'https://parceiro.example.com/hook')

      trocar(agent_bot_id: segundo.id)

      expect(response).to have_http_status(:ok)
      expect(robos_da_caixa).to eq([segundo.id])
    end
  end

  describe 'qualquer → nenhum' do
    it 'takes the platform agent out and keeps the team agents' do
      porta!(agente('Sofia'))
      bia = agente('Bia')
      area!(bia)
      conversa = pendente!

      trocar(nenhum: true)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa).to be_nil
      expect(robos_da_caixa).to be_empty
      expect(Autonomia::Agents::AgentInbox.kept.area.where(inbox_id: inbox.id).pluck(:autonomia_agent_id)).to eq([bia.id])
      expect(conversa.reload.status).to eq('open')
      expect(response.parsed_body['primeiro']).to be_nil
    end

    it 'takes the agent from another system out and hands its conversations to the team' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)
      conversa = pendente!

      trocar(nenhum: true)

      expect(response).to have_http_status(:ok)
      expect(robos_da_caixa).to be_empty
      expect(conversa.reload.status).to eq('open')
    end
  end

  describe 'área na caixa' do
    it 'refuses to make a team agent of this inbox answer first' do
      vinculo = porta!(agente('Sofia'))
      bia = agente('Bia')
      area = area!(bia)

      trocar(agent_id: bia.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('agente_ja_e_da_equipe')
      expect(porta_da_caixa.id).to eq(vinculo.id)
      expect(area.reload.deleted_at).to be_nil
    end

    it 'connects a platform agent in an inbox served only by people that has team agents' do
      porta!(agente('Sofia'))
      area!(agente('Bia'))
      trocar(nenhum: true)
      leo = agente('Leo', status: :paused, enabled: false)

      trocar(agent_id: leo.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa.autonomia_agent_id).to eq(leo.id)
    end
  end

  describe 'agente que não atende cliente' do
    it 'refuses an internal agent and keeps the current one' do
      vinculo = porta!(agente('Sofia'))
      interno = agente('Copiloto', actuation: :internal)

      trocar(agent_id: interno.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('agente_interno')
      expect(porta_da_caixa.id).to eq(vinculo.id)
    end

    it 'refuses a draft agent' do
      rascunho = agente('Clara', status: :draft, enabled: false)

      trocar(agent_id: rascunho.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('agente_rascunho')
      expect(porta_da_caixa).to be_nil
    end

    it 'refuses an agent stopped on purpose (paused with another inbox), instead of turning it on everywhere' do
      parado = agente('Leo')
      porta!(parado, create(:inbox, account: account))
      parado.update!(status: :paused)

      trocar(agent_id: parado.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('agente_parado')
      expect(parado.reload.status).to eq('paused')
    end
  end

  describe 'outra conta' do
    let(:outra) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }

    it 'does not find a platform agent of another account' do
      alheio = Autonomia::Agents::Agent.create!(account: outra, name: 'Alheio', agent_type: 'custom', status: :active, enabled: true)

      trocar(agent_id: alheio.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not find an agent from another system of another account, nor a mirror of a platform agent' do
      alheio = create(:agent_bot, account: outra, outgoing_url: 'https://x.example.com')
      espelho = porta!(agente('Sofia'), create(:inbox, account: account)).agent_bot

      trocar(agent_bot_id: alheio.id)
      expect(response).to have_http_status(:not_found)
      trocar(agent_bot_id: espelho.id)
      expect(response).to have_http_status(:not_found)
      expect(robos_da_caixa).to be_empty
    end

    it 'does not touch an inbox of another account' do
      alheia = create(:inbox, account: outra)

      put "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{alheia.id}/quem_atende",
          params: { nenhum: true }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'idempotência' do
    it 'answers 200 and changes nothing when the platform agent already answers first' do
      sofia = agente('Sofia')
      vinculo = porta!(sofia)

      trocar(agent_id: sofia.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa.id).to eq(vinculo.id)
      expect(robos_da_caixa).to eq([vinculo.agent_bot_id])
    end

    it 'answers 200 and keeps the same AgentBotInbox for the same agent from another system' do
      bot_inbox = AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)

      trocar(agent_bot_id: outro_sistema.id)

      expect(response).to have_http_status(:ok)
      expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:id)).to eq([bot_inbox.id])
    end

    it 'answers 200 for nobody when nobody answers first' do
      trocar(nenhum: true)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['primeiro']).to be_nil
    end
  end

  # Revisão do #1648: a troca é atômica também no que sai dela.
  describe 'eventos e falhas de validação' do
    it 'avisa a passagem das conversas do agente de outro sistema só depois de gravar a troca inteira' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)
      conversa = pendente!
      segundo = create(:agent_bot, account: account, name: 'Parceiro', outgoing_url: 'https://parceiro.example.com/hook')
      novo_ja_estava = []
      allow_any_instance_of(Conversation).to receive(:dispatch_bot_handoff_event).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
        novo_ja_estava << AgentBotInbox.exists?(inbox_id: inbox.id, agent_bot_id: segundo.id)
        original.call
      end

      trocar(agent_bot_id: segundo.id)

      expect(response).to have_http_status(:ok)
      expect(conversa.reload.status).to eq('open')
      expect(novo_ja_estava).to eq([true])
    end

    it 'responde 422 conexao_recusada quando uma validação de modelo falha no meio, e nada muda' do
      vinculo = porta!(agente('Sofia'))
      allow(AgentBotInbox).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AgentBotInbox.new))

      trocar(agent_bot_id: outro_sistema.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('conexao_recusada')
      expect(porta_da_caixa.id).to eq(vinculo.id)
      expect(robos_da_caixa).to eq([vinculo.agent_bot_id])
    end

    it 'lê só o agente de outro sistema ativo, e pedir o mesmo com o AgentBotInbox inativo o liga de novo' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account).update!(status: :inactive)

      get url, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['primeiro']).to be_nil

      trocar(agent_bot_id: outro_sistema.id)

      expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id, :status)).to eq([[outro_sistema.id, 'active']])
      expect(response.parsed_body['primeiro']).to include('tipo' => 'webhook', 'id' => outro_sistema.id)
    end
  end

  # Decisão do Rodrigo (#1648): a Lia (Agente de Cotação) aparece nas opções como qualquer agente.
  describe 'a Lia (Agente de Cotação)' do
    let(:config_da_lia) { { 'agente_de_cotacao' => { 'ramos' => ['auto'] } } }
    let(:lia) { agente('Lia', agent_type: 'insurance_quote', status: :paused, enabled: false, config: config_da_lia) }

    def especialista!(slug)
      Autonomia::Agents::Specialist.create!(agent: lia, account: account, slug: slug, name: slug, description: 'cota',
                                            instruction: 'Cote.')
    end

    def retrato_da_lia
      lia.reload
      { config: lia.config, instruction: lia.instruction, agent_type: lia.agent_type,
        especialistas: lia.specialists.order(:id).pluck(:slug, :instruction, :enabled) }
    end

    it 'aparece nas opções como qualquer agente' do
      lia

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['opcoes']).to include('tipo' => 'plataforma', 'id' => lia.id, 'name' => 'Lia', 'recusa' => nil)
    end

    it 'entra num canal: vira quem atende primeiro e passa a atender' do
      trocar(agent_id: lia.id)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa.autonomia_agent_id).to eq(lia.id)
      expect(lia.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'sai do único canal dela: o InboxConnector a tira e ela para' do
      porta!(lia.tap { |agente| agente.update_columns(status: Autonomia::Agents::Agent.statuses[:active], enabled: true) }) # rubocop:disable Rails/SkipsModelValidations

      trocar(nenhum: true)

      expect(response).to have_http_status(:ok)
      expect(porta_da_caixa).to be_nil
      expect(lia.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'com especialistas: entrar e sair não mexe nos especialistas nem na configuração dela' do
      especialista!('cotacao_auto')
      especialista!('cotacao_residencial')
      antes = retrato_da_lia

      trocar(agent_id: lia.id)
      expect(retrato_da_lia).to eq(antes.merge)
      trocar(agent_bot_id: outro_sistema.id)

      expect(response).to have_http_status(:ok)
      expect(retrato_da_lia).to eq(antes)
    end
  end

  describe 'pedido e permissão' do
    it 'refuses a request with more than one target' do
      trocar(agent_bot_id: outro_sistema.id, nenhum: true)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('pedido_invalido')
    end

    it 'refuses an agent who only reads the inbox settings (inbox member)' do
      membro = create(:user, account: account, role: :agent)
      create(:inbox_member, user: membro, inbox: inbox)

      trocar(agent_bot_id: outro_sistema.id, user: membro)

      expect(response).to have_http_status(:unauthorized)
      expect(robos_da_caixa).to be_empty
    end

    it 'does not find a platform agent when the account has no Agents module' do
      sem_modulo = create(:account, internal_attributes: { 'autonomia_agente_ia_por_caixa' => true })
      dono = create(:user, account: sem_modulo, role: :administrator)
      caixa = create(:inbox, account: sem_modulo)
      agent = Autonomia::Agents::Agent.create!(account: sem_modulo, name: 'Sofia', agent_type: 'custom')

      put "/api/v1/accounts/#{sem_modulo.id}/autonomia/inboxes/#{caixa.id}/quem_atende",
          params: { agent_id: agent.id }, headers: dono.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
