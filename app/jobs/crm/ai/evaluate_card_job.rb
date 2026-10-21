class Crm::Ai::EvaluateCardJob < ApplicationJob
  queue_as :low

  # trigger: 'message', ou 'mensagem_da_equipe' quando a mensagem da pessoa da equipe agendou (#1923, Crm::Ai::Observer).
  def perform(card_id, debounce_token = nil, trigger = 'message')
    return unless Crm::Ai::Config.enabled?

    card = Crm::Card.find_by(id: card_id)
    return if card.blank?

    # Memória das IAs (#1601): o que uma avaliação paga deixou pendente (o job caiu depois da chamada) é aplicado aqui,
    # sem chamar o modelo de novo.
    Crm::Memoria::Pendente.aplicar!(card)

    return if debounce_stale?(card, debounce_token)

    wait_seconds = evaluate_wait_seconds(card)
    if wait_seconds.positive?
      self.class.set(wait: wait_seconds.seconds).perform_later(card.id, debounce_token, trigger)
      return
    end

    Crm::Ai::Evaluator.new(card: card, trigger: trigger).perform
  end

  private

  def debounce_stale?(card, debounce_token)
    return false if debounce_token.blank?

    current_token = card.metadata.to_h.dig('ai', 'evaluate_token')
    current_token.present? && current_token.to_f > debounce_token.to_f
  end

  def evaluate_wait_seconds(card)
    evaluate_after = card.metadata.to_h.dig('ai', 'evaluate_after')
    return 0 if evaluate_after.blank?

    remaining = Time.parse(evaluate_after) - Time.current
    remaining.positive? ? remaining.ceil : 0
  rescue ArgumentError
    0
  end
end
