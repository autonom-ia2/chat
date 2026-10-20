class Crm::Ai::ScoreApplier
  def initialize(card:, signals:)
    @card = card
    @signals = signals
  end

  def perform
    return unless ::Crm::Ai::Config.pipeline_score_enabled?(@card.pipeline)
    return if signals_unusable?

    apply_locked
  rescue ActiveRecord::ActiveRecordError
    # Deadlock, timeout e falha de conexão sobem: o Sidekiq repete. Engolir aqui deixava o job
    # "concluído" com o score obsoleto e sem retry.
    raise
  rescue StandardError => e
    Rails.logger.error("[CRM AI score] card=#{@card.id} pipeline=#{@card.pipeline_id} #{e.class}: #{e.message}")
    nil
  end

  private

  # Sinal ausente ou malformado NÃO vira nota 0: sem base para julgar, o score anterior fica de pé.
  # O contrato do modelo é strict, mas proxy/gateway compatível pode devolver null ou tipo errado.
  def signals_unusable?
    return false if @signals.is_a?(Hash) && @signals.present?

    Rails.logger.warn("[CRM AI score] card=#{@card.id} sinais ausentes ou malformados; score preservado")
    true
  end

  # with_lock recarrega o card dentro da transação: fecha a corrida entre a avaliação em voo (que
  # pode levar dezenas de segundos no modelo) e uma nota escrita à mão nesse intervalo.
  def apply_locked
    result = nil
    @card.with_lock do
      next if manual_locked?

      turn = last_turn
      result = ::Crm::Ai::ScoreCalculator.new(
        signals: @signals,
        last_message_at: turn.last_message_at,
        customer_waiting: turn.customer_waiting,
        terminal: !@card.open?
      ).perform
      persist!(result)
    end
    result
  end

  def manual_locked?
    score_meta = ai_metadata['score'].to_h
    score_meta['source'] == 'manual' && score_meta['stage_id'].to_i == @card.stage_id
  end

  # Da última mensagem REAL (Message.chat), nunca de last_activity_at: aquele campo é empurrado por
  # nota privada e atividade de sistema, então uma nota interna hoje zeraria o decaimento de um card
  # calado há 20 dias. Mesma armadilha documentada em Crm::Conversations::LastRealMessageAt.
  # #1962: e de que lado ela veio — quem espera resposta é dado do banco, não leitura do modelo.
  def last_turn
    ::Crm::Conversations::LastTurns.for(@card.id => conversation_ids).fetch(@card.id)
  end

  def conversation_ids
    ([@card.conversation_id] + @card.card_conversations.pluck(:conversation_id)).compact.uniq
  end

  def persist!(result)
    metadata = (@card.metadata || {}).deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge(
      'score' => {
        'value' => result.value,
        'tier' => result.tier,
        'reason' => result.reason,
        'breakdown' => result.breakdown,
        # Guardados para o ScoreDecayJob recalcular o decaimento sem chamar o modelo de novo.
        'signals' => @signals.as_json,
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
