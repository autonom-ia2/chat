# A tela "Pedidos de aprovação" (#2931): os pedidos abertos de quem está pedindo, um pedido (aberto ou já respondido)
# e a resposta (Aprovar ou Recusar, com o motivo opcional). Só com a flag dos passos novos.
#
# Cada pessoa vê só os pedidos dela, e só enquanto ainda alcança o registro do pedido (PedidosDeAprovacao): o pedido de
# outra pessoa, ou de um registro que ela não vê mais, responde 404, igual a um que não existe. A pergunta sai com os
# valores lidos pelas permissões de quem olha (PedidoParaTela; o valor de venda só para quem vê valores).
class Api::V1::Accounts::Autonomia::AprovacoesController < Api::V1::Accounts::BaseController
  PEDIDOS = ::Autonomia::Automacao::PedidosDeAprovacao
  RESPOSTAS = { ok: :ok, ja_respondido: :conflict, fora_do_prazo: :unprocessable_entity }.freeze

  wrap_parameters false

  before_action :exigir_flag
  before_action :autorizar
  before_action :carregar_pedido, only: [:show, :responder]

  def index
    render json: { pedidos: PEDIDOS.abertos(Current.account, Current.user).map { |pedido| para_tela(pedido) } }
  end

  def show
    render json: para_tela(@pedido)
  end

  def responder
    resposta = PEDIDOS.responder!(@pedido, Current.user, aprovado: ActiveModel::Type::Boolean.new.cast(params[:aprovado]) == true,
                                                         motivo: params[:motivo])
    return render json: para_tela(@pedido.reload) if resposta == :ok

    render json: { error: I18n.t("autonomia.automacao.pedido.responder.#{resposta}"), pedido: para_tela(@pedido.reload) },
           status: RESPOSTAS.fetch(resposta)
  end

  private

  def exigir_flag
    head :not_found unless ::Autonomia::Automacao::Motor.passos_novos?(Current.account)
  end

  def autorizar
    authorize(::Autonomia::Automacao::Registro, "#{action_name}?", policy_class: ::Autonomia::Automacao::PedidoDeAprovacaoPolicy)
  end

  def carregar_pedido
    @pedido = PEDIDOS.da_pessoa_por_id(Current.account, Current.user, params[:id])
    head :not_found if @pedido.nil?
  end

  def para_tela(pedido) = ::Autonomia::Automacao::PedidoParaTela.new(pedido, Current.account_user).resultado
end
