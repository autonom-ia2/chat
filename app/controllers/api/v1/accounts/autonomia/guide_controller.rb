# Guia da Plataforma — onboarding, suporte e ações na conta. NÃO admin-only (qualquer perfil da conta
# usa). Gated pela elegibilidade Autonomia (ENV master + chave de IA do Kanban por conta) — o mesmo
# gate que faz o Guia nascer sozinho.
#
# Ele responde, orienta, lê a conta e PROPÕE mudanças. Escrever, só em `executar_acao`, e só depois do
# clique em confirmar na tela — nunca no caminho da pergunta.
class Api::V1::Accounts::Autonomia::GuideController < Api::V1::Accounts::BaseController
  before_action :ensure_guide_enabled

  # #572 — a pergunta NÃO é respondida aqui. Esta ação abre o pedido, põe o
  # Guia para trabalhar num job e devolve na hora; a tela busca a resposta em
  # `resposta`.
  #
  # Antes a resposta saía desta requisição, e o `rack-timeout` de produção mata
  # qualquer requisição aos 15 segundos: em 21/09/2026 uma pergunta que exigiu
  # duas leituras morreu aos 15,2s com erro 500.
  def chat
    pedido = ::Autonomia::Guide::Pedido.abrir(account: Current.account, user: Current.user)
    ::Autonomia::Guide::ChatJob.perform_later(
      pedido,
      { 'account_id' => Current.account.id, 'user_id' => Current.user.id,
        'mensagem' => params[:message].to_s, 'historico' => history_param,
        'tela' => params[:route_context].to_s, 'locale' => I18n.locale.to_s }
    )

    render json: { id: pedido, status: ::Autonomia::Guide::Pedido::PENDENTE }, status: :accepted
  end

  # O estado do pedido e, quando pronto, a resposta — com os mesmos campos que a
  # tela sempre recebeu: text, navigation, grounded, confidence, available,
  # escalate, acao e retido.
  #
  # Pedido de outra pessoa responde 404, igual a pedido que não existe: a
  # resposta foi montada com a permissão de quem perguntou.
  def resposta
    pedido = ::Autonomia::Guide::Pedido.ler(params[:id], account: Current.account, user: Current.user)
    return head :not_found if pedido.nil?

    render json: pedido
  end

  # #536 — o Guia PREPARA a ação e devolve o texto que a pessoa lê antes de
  # confirmar. Nada acontece aqui.
  def preparar_acao
    descricao = acoes.descrever(params[:acao], dados_do_pedido)
    render json: { acao: params[:acao], descricao: descricao }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Só chega aqui depois da confirmação explícita na tela.
  def executar_acao
    resultado = acoes.executar(params[:acao], dados_do_pedido)
    registrar(resultado)
    return render json: { error: resultado.mensagem }, status: :unprocessable_entity unless resultado.ok

    render json: { mensagem: resultado.mensagem }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # O corpo da ação é conteúdo livre (os campos do recurso), então não cabe strong
  # params por campo: quem autoriza é o endpoint real, chamado com o token de quem
  # pediu. Aqui só tiramos o invólucro do Rails.
  def dados_do_pedido
    bruto = params[:dados]
    return {} if bruto.blank?

    bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h.deep_symbolize_keys : bruto.to_h.deep_symbolize_keys
  end

  def acoes
    ::Autonomia::Guide::Acoes.new(account: Current.account, user: Current.user,
                                  account_user: Current.account_user)
  end

  # Quem pediu, o que mudou e quando — para uma ação feita pelo Guia nunca virar
  # mudança sem dono.
  def registrar(resultado)
    Rails.logger.info(
      "[autonomia][guide][acao] account=#{Current.account.id} user=#{Current.user.id} " \
      "acao=#{params[:acao]} ok=#{resultado.ok} registro=#{resultado.registro}"
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
