# D6 (#1601): o card mudou de status; o pedido encerrado entra (ou sai, se reabriu) na memória do cliente.
class Crm::Memoria::FechamentoJob < ApplicationJob
  queue_as :low

  def perform(card_id)
    card = Crm::Card.find_by(id: card_id)
    Crm::Memoria::Fechamento.registrar!(card) if card
  end
end
