# F3 do tema 8 (#1429) — a linha "Base de seguros" da página do agente (Autonomia::Agents::BaseDeSeguros).
# GET pede autonomia_view; comparar, atualizar e desfazer pedem autonomia_manage (BaseController). Sem a Fase 2 na conta,
# na Lia (instrução mantida) e no Guia (fora de agents_scope), 404. A chave `base` continua reservada na API genérica do
# agente (AgentsController::RESERVED_CONFIG_KEYS): só este fluxo a grava.
class Api::V1::Accounts::Autonomia::Agents::BaseDeSegurosController < Api::V1::Accounts::Autonomia::BaseController
  include DeferInteractiveAi

  BASE = ::Autonomia::Agents::BaseDeSeguros

  before_action :ensure_fase2
  before_action :fetch_agent

  # A mesma ordem de travas do Construtor e da volta por Versões (as conversas, depois o agente).
  rescue_from ActiveRecord::Deadlocked, with: :render_conflito_de_trava
  rescue_from(BASE::SemBaseNova) { aviso('sem_base_nova', :unprocessable_entity) }
  rescue_from(::Autonomia::Agents::TrocaDaBase::TrocaIndisponivel) { aviso('sem_instrucao', :unprocessable_entity) }
  rescue_from(BASE::NaoComparou, ::Autonomia::Agents::TrocaDaBase::RetratoMudou) { aviso('comparar_antes', :unprocessable_entity) }
  rescue_from(BASE::VersaoMudou) { aviso('base_mudou', :conflict) }
  rescue_from(::Autonomia::Agents::TrocaDaBase::BaseMudou) { aviso('desfazer_fechado', :conflict) }
  rescue_from(BASE::Limite::Excedido) { |erro| aviso("comparar_#{erro.motivo}", :too_many_requests) }

  def show
    render json: payload
  end

  # O antes e depois (BaseDeSeguros::Comparacao) vai para um job; a tela busca a resposta no poll_url. Com uma comparação
  # pronta desta versão nos últimos 2 minutos (Comparada), devolve ela na hora: reabrir a gaveta mostra o mesmo antes e
  # depois, sem gastar a vez nem mandar esperar, e quem pediu passa a ter visto.
  def comparar
    versao = servico.marca_para_trocar!['versao']
    pronta = BASE::Comparada.resultado(@agent, versao, I18n.locale.to_s)
    return mostrar_comparacao_pronta(versao, pronta) if pronta

    BASE::Limite.reservar!(@agent)
    defer_interactive_ai('agent_base_compare', { agent_id: @agent.id })
  end

  # `versao` (obrigatória): a da base nova que a pessoa comparou. Sem ela, ou sem o antes e depois dela por esta pessoa,
  # 422 (comparar_antes); outra versão, 409. Em todos, nada muda.
  def atualizar
    versao = params[:versao].to_s
    raise BASE::NaoComparou if versao.blank?

    servico.atualizar!(created_by: Current.user, versao: versao, account_user: Current.account_user)
    render json: payload
  end

  def desfazer
    @agent.desfazer_troca_da_base!(created_by: Current.user)
    render json: payload
  end

  private

  def aviso(codigo, status)
    render json: { error: I18n.t("autonomia.base_de_seguros.#{codigo}"), code: codigo }, status: status
  end

  def mostrar_comparacao_pronta(versao, pronta)
    BASE::Comparada.marcar_quem_viu!(@agent, Current.account_user, versao)
    render json: pronta
  end

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
