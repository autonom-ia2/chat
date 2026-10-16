# A avaliação conjunta dos cards que uma mensagem tocou (#1693), depois do debounce de sempre. Card que ganhou um
# agendamento mais novo (outra mensagem, troca de foco depois desta) sai: quem o avalia é o job mais novo.
class Crm::Ai::EvaluateCardsJob < ApplicationJob
  queue_as :low

  def perform(card_ids, principal_id, token)
    return unless Crm::Ai::Config.enabled?

    cards = Crm::Card.where(id: card_ids).index_by(&:id).values_at(*card_ids).compact
    cards = cards.reject { |card| card.metadata.to_h.dig('ai', 'evaluate_token').to_f > token.to_f }
    return if cards.empty?

    Crm::Ai::AvaliacaoConjunta.new(cards: cards, principal: principal(cards, principal_id)).perform
  end

  # O principal da decisão; se ele saiu (agendamento mais novo, card fechado), o card em foco, se está entre eles.
  def principal(cards, principal_id)
    cards.find { |card| card.id == principal_id } || cards.find { |card| Crm::Cards::CurrentSubject.card?(card) }
  end
end
