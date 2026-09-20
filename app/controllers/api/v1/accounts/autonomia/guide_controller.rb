# Guia da Plataforma — endpoint READ-ONLY de onboarding/suporte. NÃO admin-only (qualquer perfil da
# conta usa). Gated pela elegibilidade Autonomia (ENV master + chave de IA do Kanban por conta) — o
# mesmo gate que faz o Guia nascer sozinho. Nunca opera/escreve: só responde, orienta e sugere a tela.
class Api::V1::Accounts::Autonomia::GuideController < Api::V1::Accounts::BaseController
  before_action :ensure_guide_enabled

  def chat
    result = ::Autonomia::Guide::Chat.new(
      account: Current.account,
      user: Current.user,
      message: params[:message],
      history: history_param,
      route_context: params[:route_context]
    ).perform

    render json: {
      text: result.text,
      navigation: result.navigation,
      grounded: result.grounded,
      confidence: result.confidence,
      available: result.available,
      escalate: result.escalate,
      acao: result.acao
    }
  end

  # #536 — o Guia PREPARA a ação e devolve o texto que a pessoa lê antes de
  # confirmar. Nada acontece aqui.
  def preparar_acao
    descricao = acoes.descrever(params[:acao], params[:dados] || {})
    render json: { acao: params[:acao], descricao: descricao }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Só chega aqui depois da confirmação explícita na tela.
  def executar_acao
    resultado = acoes.executar(params[:acao], params[:dados] || {})
    registrar(resultado)
    return render json: { error: resultado.mensagem }, status: :unprocessable_entity unless resultado.ok

    render json: { mensagem: resultado.mensagem }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def acoes
    ::Autonomia::Guide::Acoes.new(account: Current.account, user: Current.user,
                                  account_user: Current.account_user)
  end

  # Quem pediu, o que mudou e quando — para uma ação feita pelo Guia nunca virar
  # mudança sem dono.
  def registrar(resultado)
    Rails.logger.info(
      "[autonomia][guide][acao] account=#{Current.account.id} user=#{Current.user.id} " \
      "acao=#{params[:acao]} ok=#{resultado.ok} registro=#{resultado.registro&.id}"
    )
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end

  # Robusto: aceita só itens hash/params (string/símbolo); um item malformado (ex.: "x") não derruba
  # o endpoint com TypeError antes do rescue do serviço.
  def history_param
    Array(params[:history]).filter_map do |h|
      next unless h.is_a?(Hash) || h.is_a?(ActionController::Parameters)

      { role: h[:role].to_s, content: h[:content].to_s }
    end
  end
end
