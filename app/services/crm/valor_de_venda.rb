# Quem vê os valores de venda em R$ do CRM (#2075, lote 13 das funções personalizadas): o valor do card, as somas, as
# metas em R$ e as razões tiradas do dinheiro (ROI, % da meta, taxa de ganho por valor). Contagens ficam para todos.
# Decisões do Rodrigo (22/10):
# - Administrador vê. Agente sem função personalizada continua vendo, como antes.
# - Função personalizada vê só com `sales_value_view`. É chave protegida (só o administrador entrega), então o
#   `crm_admin`, que quem cuida de Pessoas repassa, não a liga.
# - Sem a chave, a pessoa ainda vê o valor dos cards de que é dona (`owner_id`) e os próprios números de "Só eu".
# - Sem a chave dá para trabalhar: mover e ganhar o card continua; a resposta só não traz o valor, e editar o card não
#   muda o valor que a pessoa não vê.
#
#   Crm::ValorDeVenda.ve?(account_user)              -> true | false
#   Crm::ValorDeVenda.ve_o_card?(account_user, card) -> true | false (inclui o card de que a pessoa é dona)
#   Crm::ValorDeVenda.oculta_card!(payload)          -> o payload com value_cents nil e value_hidden: true
module Crm::ValorDeVenda
  CHAVE = 'sales_value_view'.freeze

  module_function

  def ve?(account_user)
    return false if account_user.blank?
    return true if account_user.administrator?

    role = account_user.try(:custom_role)
    return true if role.blank?

    role.permissions.include?(CHAVE)
  end

  def ve_o_card?(account_user, card)
    ve?(account_user) || dono?(account_user, card)
  end

  def dono?(account_user, card)
    account_user.present? && card.owner_id.present? && card.owner_id == account_user.user_id
  end

  def oculta_card!(payload)
    payload[:value_cents] = nil
    payload[:value_hidden] = true
    payload
  end
end
