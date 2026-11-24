# Refaz o resumo de compras de pessoas de uma conta (Relacionamentos::Compras::Recalcular, #3097). `contact_ids` nil
# refaz a conta inteira. `disparar`: 'venda', 'tempo' ou false (o ajuste das faixas), como no serviço.
#
# #3100 — logo depois, a compra vira carimbo do cartão fidelidade (Fidelidade::DarPelaCompra), para as mesmas pessoas e
# com a mesma trava da conta. O ajuste das faixas não mexe em compra nenhuma e fica de fora.
class Relacionamentos::Compras::RecalcularJob < ApplicationJob
  queue_as :low

  def perform(account_id, contact_ids, disparar)
    account = Account.find_by(id: account_id)
    return unless account

    Relacionamentos::Compras::Recalcular.new(account, contact_ids: contact_ids, disparar: disparar ? disparar.to_sym : false).call
    Fidelidade::DarPelaCompra.new(account, contact_ids: contact_ids).call if disparar
  end
end
