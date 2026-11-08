class Crm::Ai::EvaluateCardJob < ApplicationJob
  queue_as :low

  # trigger: 'message', ou 'mensagem_da_equipe' quando a mensagem da pessoa da equipe agendou (#1923, Crm::Ai::Observer).
  # tentativa (#2154): quantas vezes a avaliação depois da fala do agente já voltou porque o turno seguinte estava em
  # curso (Crm::Ai::AvaliacaoDepoisDaFala); 0 nos outros gatilhos.
  def perform(card_id, debounce_token = nil, trigger = 'message', tentativa = 0)
    return unless Crm::Ai::Config.enabled?

    card = Crm::Card.find_by(id: card_id)
    return if card.blank?

    # Memória das IAs (#1601): o que uma avaliação paga deixou pendente (o job caiu depois da chamada) é aplicado aqui,
    # sem chamar o modelo de novo.
    Crm::Memoria::Pendente.aplicar!(card)

    return if debounce_stale?(card, debounce_token)

    wait_seconds = evaluate_wait_seconds(card)
    if wait_seconds.positive?
      # O 4º argumento só quando há tentativa: o worker antigo, no meio do deploy, recebe o job de sempre.
      self.class.set(wait: wait_seconds.seconds).perform_later(card.id, debounce_token, trigger, *tentativa_extra(tentativa))
      return
    end

    # Sem tentativa (todo gatilho menos a volta da avaliação depois da fala), a chamada de sempre.
    opcoes = tentativa.to_i.positive? ? { tentativa: tentativa.to_i } : {}
    Crm::Ai::Evaluator.new(card: card, trigger: trigger, **opcoes).perform
  end

  private

  def tentativa_extra(tentativa) = tentativa.to_i.positive? ? [tentativa.to_i] : []

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
