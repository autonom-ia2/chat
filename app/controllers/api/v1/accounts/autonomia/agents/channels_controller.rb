class Api::V1::Accounts::Autonomia::Agents::ChannelsController < Api::V1::Accounts::Autonomia::BaseController
  PAPEL_AREA = 'area'.freeze
  # Código do Areas.caixa_aceita_area? -> motivo da tela (area_errors).
  MOTIVO_DA_CAIXA = { principal_parado: :sem_principal, fase2_desligada: :fase2_off }.freeze

  before_action :fetch_agent
  before_action :fetch_inbox, only: [:create, :destroy]

  # Lista os vínculos ativos do agente + inboxes elegíveis da conta (para o seletor de canal).
  # #1433: a área desmarcada fica arquivada (deleted_at) e não é canal; cada vínculo diz o papel.
  def index
    load_index
  end

  # `ativar: true` (#1366) — "Começar a atender neste canal": liga o agente parado junto com o vínculo.
  # `papel: 'area'` (#1433, tema 13) — "agente da equipe": entra na caixa como área (recebe quando alguém passa) e já
  # liga, pelo Autonomia::Agents::Areas. Só com a Fase 2 ligada na conta.
  def create
    return create_area if params[:papel] == PAPEL_AREA

    ativar = ActiveModel::Type::Boolean.new.cast(params[:ativar]) == true
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox, ativar: ativar).perform(connect: true)
    return render_unprocessable(connector_error(result.error)) unless result.success?

    @agent_inbox = result.agent_inbox
    load_index
    render :index, status: :created
  end

  def destroy
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox).perform(connect: false)
    return render_unprocessable(connector_error(result.error)) unless result.success?

    head :no_content
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def load_index
    @agent_inboxes = @agent.agent_inboxes.kept.includes(:inbox).order(created_at: :desc)
    @eligible_inboxes = eligible_inboxes
  end

  # Idempotente, ANTES das recusas: a área já ativa do mesmo agente nesta caixa responde 200 com o mesmo vínculo (a
  # tela repete o pedido depois de uma falha no meio, sem saber o que já entrou; o principal pode ter parado depois).
  # As outras recusas previsíveis respondem antes do vínculo, com o motivo; o Areas confere de novo com agente e caixa
  # travados (o principal atendendo, ou a caixa sem agente externo quando não há principal).
  def create_area
    return responder_area_ja_ativa if area_ativa?

    recusa = recusa_de_area
    return render_unprocessable(area_error(recusa)) if recusa

    # `de_rascunho`: esta é a criação do agente da equipe; o rascunho com a conversa de criação fechada entra e liga.
    @agent_inbox = ::Autonomia::Agents::Areas.vincular!(agent: @agent, inbox: @inbox, ativar: true, de_rascunho: true)
    load_index
    render :index, status: :created
  rescue ::Autonomia::Agents::Areas::AgenteInterno, ::Autonomia::Agents::Areas::AgenteDeSistema
    render_unprocessable(area_error(:agent_internal))
  rescue ::Autonomia::Agents::Areas::CaixaNaoAceitaArea => e
    render_unprocessable(area_error(MOTIVO_DA_CAIXA.fetch(e.codigo, :generic)))
  rescue ::Autonomia::Agents::Areas::AgenteRascunho
    render_unprocessable(area_error(:rascunho))
  rescue ::Autonomia::Agents::Areas::AgenteNaoPodeSerArea
    render_unprocessable(area_error(:nao_pode_ser_area))
  rescue ActiveRecord::RecordNotUnique
    render_unprocessable(area_error(:already_linked))
  rescue ActiveRecord::RecordInvalid
    render_unprocessable(area_error(:generic))
  end

  def recusa_de_area
    return :fase2_off unless ::Autonomia::Agents::Fase2.ligada?(Current.account)
    return :agent_internal if @agent.actuation_internal?
    # Já é o principal (porta) desta caixa: não pode ser também da equipe dela.
    return :already_linked if ::Autonomia::Agents::AgentInbox.kept.porta.exists?(autonomia_agent_id: @agent.id, inbox_id: @inbox.id)

    recusa_da_caixa
  end

  def responder_area_ja_ativa
    @agent_inbox = ::Autonomia::Agents::AgentInbox.kept.area.find_by(autonomia_agent_id: @agent.id, inbox_id: @inbox.id)
    load_index
    render :index, status: :ok
  end

  def area_ativa?
    ::Autonomia::Agents::AgentInbox.kept.area.exists?(autonomia_agent_id: @agent.id, inbox_id: @inbox.id)
  end

  # A regra é do Areas.caixa_aceita_area? (leitor único): principal atendendo ou caixa só de pessoas.
  def recusa_da_caixa
    MOTIVO_DA_CAIXA[::Autonomia::Agents::Areas.caixa_aceita_area?(@inbox).codigo]
  end

  # Inboxes da conta que ainda não têm nenhum bot (nem webhook/Gabriela, nem agente nativo).
  def eligible_inboxes
    connected_ids = ::Autonomia::Agents::AgentInbox.kept.where(account: Current.account).pluck(:inbox_id)
    Current.account.inboxes
           .where.missing(:agent_bot_inbox)
           .where.not(id: connected_ids)
  end

  def connector_error(code)
    I18n.t("autonomia.agents.operate.connect_errors.#{code}",
           default: I18n.t('autonomia.agents.operate.connect_errors.generic'))
  end

  def area_error(code)
    I18n.t("autonomia.agents.operate.area_errors.#{code}", nome: @agent.name, canal: @inbox.name)
  end
end
