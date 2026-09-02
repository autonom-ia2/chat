# Recalcula o score dos cards SEM chamar o modelo.
#
# Por que existe: o decaimento por silêncio só acontecia quando havia nova avaliação, e o
# StaleCardsJob (de propósito) não reavalia card sem atividade nova. Resultado: card pontuado 90
# ficava 90 para sempre. A regra "silêncio derruba a nota sozinho" simplesmente não acontecia.
#
# Como: os sinais que a IA classificou ficam gravados em metadata.ai.score.signals. Recalcular é
# aritmética sobre eles mais o tempo decorrido — custo zero de IA.
class Crm::Ai::ScoreDecayJob < ApplicationJob
  queue_as :scheduled_jobs

  # Teto por execução: a varredura é periódica (3h) e não pode virar job de horas numa conta grande.
  # O que sobrar entra na próxima rodada — decaimento é idempotente e não perde nada.
  MAX_CARDS_PER_RUN = 2_000
  BATCH_SIZE = 200

  def perform
    @processed = 0

    Crm::Pipeline.active.find_each do |pipeline|
      next unless Crm::Ai::Config.pipeline_score_enabled?(pipeline)

      zero_closed_cards(pipeline)
      decay_open_cards(pipeline)
      break if budget_over?
    end
  end

  private

  def budget_over?
    @processed >= MAX_CARDS_PER_RUN
  end

  def remaining_budget
    MAX_CARDS_PER_RUN - @processed
  end

  def decay_open_cards(pipeline)
    scored_cards_for(pipeline).open.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      break if budget_over?

      cards = batch.first(remaining_budget)
      last_messages = last_message_map(cards)
      cards.each { |card| safely_apply(card, last_messages[card.id]) }
      @processed += cards.size
    end
  end

  # Card ganho, perdido ou arquivado mantinha a nota e continuava ranqueando como urgente em
  # qualquer consulta que inclua cards fechados. O Evaluator nunca chega neles (só avalia abertos).
  def zero_closed_cards(pipeline)
    scored_cards_for(pipeline).where.not(status: Crm::Card.statuses[:open]).in_batches(of: BATCH_SIZE) do |relation|
      break if budget_over?

      ids = relation.limit(remaining_budget).pluck(:id)
      Crm::Card.where(id: ids).update_all(score: 0, updated_at: Time.current) if ids.present?
      @processed += ids.size
    end
  end

  def scored_cards_for(pipeline)
    Crm::Card.where(account_id: pipeline.account_id, pipeline_id: pipeline.id)
             .where(Crm::Card.arel_table[:score].gt(0))
  end

  # Uma consulta agregada para o lote inteiro, em vez de uma por conversa por card (era N+1: até
  # duas queries por card a cada 3 horas).
  def last_message_map(cards)
    fallback_by_card = cards.index_with(&:last_message_at).compact
    by_card = conversation_ids_by_card(cards)
    all_ids = by_card.values.flatten.compact.uniq
    return fallback_by_card if all_ids.empty?

    per_conversation = Message.chat.where(conversation_id: all_ids).group(:conversation_id).maximum(:created_at)
    by_card.each_with_object(fallback_by_card) do |(card_id, ids), result|
      result[card_id] = [result[card_id], ids.filter_map { |id| per_conversation[id] }.max].compact.max
    end
  end

  def conversation_ids_by_card(cards)
    by_card = Crm::CardConversation.where(account_id: cards.map(&:account_id).uniq, card_id: cards.map(&:id))
                                   .pluck(:card_id, :conversation_id)
                                   .group_by(&:first)
                                   .transform_values { |rows| rows.map(&:last) }
    cards.each { |card| (by_card[card.id] ||= []) << card.conversation_id if card.conversation_id }
    by_card
  end

  def safely_apply(card, last_message_at)
    apply(card, last_message_at)
  rescue ActiveRecord::ActiveRecordError, ArgumentError, TypeError => e
    Rails.logger.warn(
      "[Crm::Ai::ScoreDecayJob] skipped card_id=#{card.id} account_id=#{card.account_id} " \
      "pipeline_id=#{card.pipeline_id} error_class=#{e.class.name}"
    )
  end

  def apply(card, last_message_at)
    card.with_lock do
      # Releitura dentro do lock: o ScoreApplier ou uma edição humana podem ter gravado entre a
      # leitura do lote e agora. Sem isso, o job sobrescreveria a versão mais nova.
      score_meta = card.metadata.to_h.dig('ai', 'score').to_h
      unless score_meta['source'] == 'manual' || card.score.to_i <= 0
        anchor = decay_anchor(score_meta, last_message_at)

        if anchor.present?
          result = recalculate(score_meta, anchor)
          persist!(card, score_meta, result, anchor) unless result[:value] == card.score
        end
      end
    end
  end

  # Âncora IMUTÁVEL do decaimento. Antes o job usava calculated_at e depois sobrescrevia esse mesmo
  # campo com o horário da rodada: na execução seguinte a âncora parecia nova e o score subia de
  # volta. Agora a âncora é gravada uma vez e o calculated_at só registra quando recalculamos.
  def decay_anchor(score_meta, last_message_at)
    return last_message_at if last_message_at.present?

    parse_time(score_meta['decay_anchor_at']) || parse_time(score_meta['calculated_at'])
  end

  # Card pontuado pela versão anterior não tem `signals` gravados. Em vez de ignorá-lo para sempre
  # (justamente o card antigo e parado, que mais precisa esfriar), aplicamos decaimento puro sobre a
  # nota-base guardada.
  def recalculate(score_meta, anchor)
    signals = score_meta['signals']
    base = (score_meta['base_value'] || score_meta['value']).to_i

    if signals.present?
      computed = Crm::Ai::ScoreCalculator.new(signals: signals, last_message_at: anchor).perform
      { value: computed.value, tier: computed.tier, base: base }
    else
      value = [base + decay_points(anchor), 0].max
      { value: value, tier: Crm::Ai::ScoreCalculator.tier_for(value), base: base }
    end
  end

  def decay_points(anchor)
    idle = ((Time.current - anchor) / 1.day).floor - Crm::Ai::ScoreCalculator::DECAY_GRACE_DAYS
    return 0 if idle <= 0

    -(idle * Crm::Ai::ScoreCalculator::DECAY_PER_DAY)
  end

  def persist!(card, score_meta, result, anchor)
    metadata = card.metadata.deep_dup
    metadata['ai'] ||= {}
    metadata['ai']['score'] = score_meta.merge(
      'value' => result[:value],
      'tier' => result[:tier],
      'base_value' => result[:base],
      'decay_anchor_at' => anchor.iso8601,
      'calculated_at' => Time.current.iso8601
    )
    card.update_columns(score: result[:value], metadata: metadata, updated_at: Time.current)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
