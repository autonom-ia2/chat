class Crm::Ai::StaleCardsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless Crm::Ai::Config.enabled?

    Crm::Pipeline.active.find_each do |pipeline|
      settings = Crm::Ai::Config.pipeline_ai_settings(pipeline)
      next if settings[:enabled] == false

      stale_hours = settings[:stale_hours].presence || Crm::Ai::Config::DEFAULT_STALE_HOURS
      cutoff = stale_hours.to_i.hours.ago
      # IA entende a conversa F3: com a flag `crm_ia_fecha_card`, a avaliação do card parado sai marcada, e o silêncio
      # nunca fecha card (Crm::Ai::FecharCard). Sem a flag, o job de sempre.
      gatilho = Crm::Ai::FecharCard.ligada?(pipeline.account) ? [nil, Crm::Ai::FecharCard::TRIGGER_CARD_PARADO] : []

      pipeline.cards.open.where('last_activity_at < ?', cutoff).find_each do |card|
        next if already_evaluated_since_last_activity?(card)
        # Multifunil (#1147): o Evaluator pula o card que não é o assunto atual; enfileirar seria um job à toa a cada ciclo.
        next unless Crm::Cards::CurrentSubject.card?(card)

        Crm::Ai::EvaluateCardJob.perform_later(card.id, *gatilho)
      end
    end
  end

  private

  # Custo: NÃO reavaliar card cuja última avaliação já é posterior à última atividade.
  # `last_activity_at` só avança com mensagem nova (CardSyncer); a avaliação grava
  # `ai.last_evaluated_at` mas NÃO mexe em `last_activity_at`. Sem esta guarda, todo card
  # parado seria reclassificado a cada 6h indefinidamente, sem nada novo pra classificar.
  def already_evaluated_since_last_activity?(card)
    return false if card.last_activity_at.blank?

    last_evaluated_at = card.metadata.to_h.dig('ai', 'last_evaluated_at')
    return false if last_evaluated_at.blank?

    parsed = Time.zone.parse(last_evaluated_at)
    parsed.present? && parsed >= card.last_activity_at
  rescue ArgumentError
    false
  end
end
