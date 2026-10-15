# chat#1648 — a aba "Agente de IA" da caixa: quem atende primeiro, quem também recebe quando alguém passa, e a troca.
# Fora da base dos Agentes (sem flag de módulo, de jornada ou de Fase 2), mas atrás da chave da conta
# Autonomia::Agents::AgenteIaPorCaixa (404 sem ela). Troca também agente de outro sistema. Agente da plataforma só com o
# módulo de Agentes ligado na conta (404 sem ele, como a API deles).
# Ler: a autorização da tela de configuração da caixa (InboxPolicy#settings?). Trocar: a do set_agent_bot
# (InboxPolicy#set_agent_bot?, inbox_manage) e, quando a troca mexe em agente da plataforma (o que sai ou o que entra),
# também autonomia_manage: inbox_manage pode ser delegada por função, e mexer em agente da plataforma é da função de
# Agentes. Troca só entre agentes de outro sistema (ou com ninguém) basta inbox_manage.
class Api::V1::Accounts::Autonomia::QuemAtendeController < Api::V1::Accounts::BaseController
  before_action :ensure_flag
  before_action :fetch_inbox

  # { agentes: [{ tipo, id, name, papel, avatar_url }], primeiro: { tipo, id, name } | null,
  #   opcoes: [{ tipo, id, name, recusa }] }
  def show
    authorize @inbox, :settings?
    render json: leitura
  end

  # Um destes: `agent_id` (agente da plataforma), `agent_bot_id` (agente de outro sistema) ou `nenhum: true`. Responde a
  # leitura nova; 422 { error, code } na recusa.
  def update
    authorize @inbox, :set_agent_bot?
    alvo = alvo_do_pedido
    return recusar(:pedido_invalido) if alvo.nil?
    raise Pundit::NotAuthorizedError if mexe_em_agente_da_plataforma?(alvo) && !Current.account_user.permission_granted?('autonomia_manage')

    resultado = ::Autonomia::Agents::TrocarQuemAtende.new(inbox: @inbox, alvo: alvo).perform
    return recusar(resultado.code) unless resultado.ok?

    render json: leitura
  end

  private

  # Só nas contas com a aba "Agente de IA" por caixa (#1648); fora delas a caixa tem a aba Robô de sempre.
  def ensure_flag
    head :not_found unless ::Autonomia::Agents::AgenteIaPorCaixa.ligada?(Current.account)
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def leitura
    quem = ::Autonomia::Agents::QuemAtendeACaixa
    { agentes: quem.agentes(@inbox), primeiro: quem.primeiro(@inbox), opcoes: quem.opcoes(@inbox) }
  end

  # nil quando o pedido não diz exatamente um alvo. Agente fora da conta, de sistema, apagado ou espelho: 404.
  def alvo_do_pedido
    pedidos = [params[:agent_id].presence, params[:agent_bot_id].presence, nenhum?.presence].compact
    return if pedidos.size != 1

    return { tipo: 'nenhum' } if nenhum?
    return { tipo: 'plataforma', agent: agente_da_plataforma } if params[:agent_id].present?

    { tipo: 'webhook', agent_bot: ::Autonomia::Agents::QuemAtendeACaixa.agentes_de_outro_sistema(Current.account).find(params[:agent_bot_id]) }
  end

  # O agente que entra ou a porta que sai é da plataforma. A porta é lida antes da trava; uma porta que entrar depois é
  # de um agente que a troca não travou, e ela recusa com mudou_agora.
  def mexe_em_agente_da_plataforma?(alvo)
    alvo[:tipo] == 'plataforma' || ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).porta.exists?
  end

  def nenhum?
    ActiveModel::Type::Boolean.new.cast(params[:nenhum]) == true
  end

  def agente_da_plataforma
    raise ActiveRecord::RecordNotFound unless ::Autonomia::Agents::Config.enabled?(Current.account)

    ::Autonomia::Agents::Agent.kept.where(account: Current.account).where("config->>'system_key' IS NULL").find(params[:agent_id])
  end

  def recusar(code)
    render json: { error: I18n.t("autonomia.agents.quem_atende.#{code}"), code: code.to_s }, status: :unprocessable_entity
  end
end
