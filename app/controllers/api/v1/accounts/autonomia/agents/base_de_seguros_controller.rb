# F3 do tema 8 (#1429) — a linha "Base de seguros" da página do agente (Autonomia::Agents::BaseDeSeguros).
# GET pede autonomia_view; comparar, atualizar e desfazer pedem autonomia_manage (BaseController). Sem a Fase 2 na conta,
# na Lia (instrução mantida) e no Guia (fora de agents_scope), 404. A chave `base` continua reservada na API genérica do
# agente (AgentsController::RESERVED_CONFIG_KEYS): só este fluxo a grava.
class Api::V1::Accounts::Autonomia::Agents::BaseDeSegurosController < Api::V1::Accounts::Autonomia::BaseController
  include DeferInteractiveAi

  BASE = ::Autonomia::Agents::BaseDeSeguros

  before_action :ensure_fase2
  before_action :fetch_agent

  rescue_from BASE::SemBaseNova, ::Autonomia::Agents::TrocaDaBase::TrocaIndisponivel do
    render_unprocessable(I18n.t('autonomia.base_de_seguros.sem_base_nova'))
  end
  rescue_from BASE::VersaoMudou, ::Autonomia::Agents::TrocaDaBase::BaseMudou do
    render json: { error: I18n.t('autonomia.base_de_seguros.base_mudou'), code: 'base_mudou' }, status: :conflict
  end
  rescue_from BASE::Limite::Excedido do |erro|
    codigo = "comparar_#{erro.motivo}"
    render json: { error: I18n.t("autonomia.base_de_seguros.#{codigo}"), code: codigo }, status: :too_many_requests
  end

  def show
    render json: payload
  end

  # O antes e depois (BaseDeSeguros::Comparacao) vai para um job; a tela busca a resposta no poll_url.
  def comparar
    raise BASE::SemBaseNova unless servico.to_h&.dig(:pode_atualizar)

    BASE::Limite.reservar!(@agent)
    defer_interactive_ai('agent_base_compare', { agent_id: @agent.id })
  end

  # `versao`: a da base nova que a pessoa viu; outra versão é 409 e nada muda.
  def atualizar
    servico.atualizar!(created_by: Current.user, versao: params[:versao].presence&.to_s)
    render json: payload
  end

  def desfazer
    @agent.desfazer_troca_da_base!(created_by: Current.user)
    render json: payload
  end

  private

  def ensure_fase2
    head :not_found unless ::Autonomia::Agents::Fase2.ligada?(Current.account)
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
    raise ActiveRecord::RecordNotFound unless BASE.elegivel?(@agent)
  end

  def servico
    BASE.new(@agent)
  end

  # Relido: depois de atualizar ou desfazer, a resposta é o estado gravado. Sem linha, `situacao` nula.
  def payload
    BASE.new(@agent.reload).to_h || { situacao: nil }
  end
end
