# Refaz o resumo de compras de pessoas de uma conta (Relacionamentos::Compras::Recalcular, #3097). `contact_ids` nil
# refaz a conta inteira. `disparar`: 'venda', 'tempo' ou false (o ajuste das faixas), como no serviço.
class Relacionamentos::Compras::RecalcularJob < ApplicationJob
  queue_as :low

  def perform(account_id, contact_ids, disparar)
    account = Account.find_by(id: account_id)
    return unless account

    Relacionamentos::Compras::Recalcular.new(account, contact_ids: contact_ids, disparar: disparar&.to_sym).call
  end
end
