# Tempo de solução de um funil de Atender (#1498): da criação do card até o último Resolvido (closed_at), sem o tempo em que ele esteve
# numa etapa "Esperando o cliente" (categoria espera, vinda do modelo). Funil sem essa categoria conta o tempo
# inteiro. Média e mediana em segundos, sobre os cards resolvidos no período (no máximo MAX_CARDS, os mais
# recentes, para a conta não pesar).
class Crm::Reports::ResolutionTime
  MAX_CARDS = 2_000
  PAUSE_CATEGORY = 'espera'.freeze

  def initialize(pipeline:, cards:)
    @pipeline = pipeline
    @cards = cards
  end

  def perform
    cards = @cards.order(closed_at: :desc).limit(MAX_CARDS).pluck(:id, :created_at, :closed_at, :stage_id)
    return { count: 0, average_seconds: nil, median_seconds: nil } if cards.empty?

    moves = pause_stage_ids.empty? ? {} : moves_by_card(cards.map(&:first))
    durations = cards.map { |id, created_at, closed_at, stage_id| duration(created_at, closed_at, stage_id, moves[id] || []) }
    { count: durations.size, average_seconds: (durations.sum / durations.size).round, median_seconds: median(durations).round }
  end

  private

  def pause_stage_ids
    @pause_stage_ids ||= @pipeline.stages.select { |stage| (stage.metadata || {})['category'] == PAUSE_CATEGORY }.map(&:id)
  end

  # Mudanças de etapa de cada card, em ordem: [quando, de, para].
  def moves_by_card(card_ids)
    Crm::Activity.where(card_id: card_ids, event_type: 'move').order(:created_at)
                 .pluck(:card_id, :created_at, :payload)
                 .group_by(&:first)
                 .transform_values { |rows| rows.map { |_, at, payload| [at, payload.to_h['from_stage_id'], payload.to_h['to_stage_id']] } }
  end

  def duration(created_at, closed_at, stage_id, moves)
    total = closed_at - created_at
    paused = paused_seconds(created_at, closed_at, moves.first&.second || stage_id, moves)
    [total - paused, 0].max.to_f
  end

  # Percorre a linha do tempo: cada trecho fica na etapa em que o card estava; soma os trechos de pausa.
  def paused_seconds(created_at, closed_at, first_stage_id, moves)
    return 0 if pause_stage_ids.empty?

    stage = first_stage_id
    from = created_at
    paused = moves.sum do |at, _from_stage, to_stage|
      segment = pause_stage_ids.include?(stage.to_i) ? (at.clamp(created_at, closed_at) - from) : 0
      from = at.clamp(created_at, closed_at)
      stage = to_stage
      [segment, 0].max
    end
    paused + (pause_stage_ids.include?(stage.to_i) ? [closed_at - from, 0].max : 0)
  end

  def median(values)
    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
