# Os pedidos do passo "Pedir aprovação" (#2931) do lado de quem aprova. Qualquer pessoa da conta abre a tela: quem
# aprova é a equipe, não quem monta a automação, então não pede a chave de automações. O que cada pessoa vê e responde
# é decidido pedido a pedido (PedidosDeAprovacao: só os dela, e só enquanto ela alcança o registro).
class Autonomia::Automacao::PedidoDeAprovacaoPolicy < ApplicationPolicy
  def index? = da_conta?
  def show? = da_conta?
  def responder? = da_conta?

  private

  def da_conta? = account_user.present?
end
