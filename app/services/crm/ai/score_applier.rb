class Crm::Ai::ScoreApplier
  def initialize(card:, signals:)
    @card = card
    @signals = signals
  end

  # Best-effort: falha de score nunca derruba a avaliação do card.
  def perform
    return unless ::Crm::Ai::Config.pipeline_score_enabled?(@card.pipeline)
    return if manual_locked?

    result = ::Crm::Ai::ScoreCalculator.new(
      signals: @signals,
      last_message_at: last_message_at,
      terminal: !@card.open?
    ).perform

    persist!(result)
    result
  rescue StandardError => e
    Rails.logger.error("[CRM AI score] #{e.class}: #{e.message}")
    nil
  end

  private

  def manual_locked?
    score_meta = ai_metadata['score'].to_h
    score_meta['source'] == 'manual' && score_meta['stage_id'].to_i == @card.stage_id
  end

  # Da ÚLTIMA MENSAGEM, nunca de entered_stage_at nem updated_at: um card pode mudar de estágio
  # semanas depois da conversa morrer, e aí pareceria fresco.
  def last_message_at
    ids = ([@card.conversation_id] + @card.card_conversations.pluck(:conversation_id)).compact.uniq
    return nil if ids.empty?

    Conversation.where(id: ids).maximum(:last_activity_at)
  end

  def persist!(result)
    metadata = (@card.metadata || {}).deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge(
      'score' => {
        'value' => result.value,
        'tier' => result.tier,
        'reason' => result.reason,
        'breakdown' => result.breakdown,
        'source' => 'ai',
        'stage_id' => @card.stage_id,
        'calculated_at' => Time.current.iso8601
      }
    )
    @card.update!(score: result.value, metadata: metadata)
  end

  def ai_metadata
    (@card.metadata || {}).fetch('ai', {}).to_h
  end
end
