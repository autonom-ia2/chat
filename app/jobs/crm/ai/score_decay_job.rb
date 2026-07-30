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

  def perform
    Crm::Pipeline.active.find_each do |pipeline|
      next unless Crm::Ai::Config.pipeline_score_enabled?(pipeline)

      decay_open_cards(pipeline)
      zero_closed_cards(pipeline)
    end
  end

  private

  def decay_open_cards(pipeline)
    pipeline.cards.open.where('score > 0').find_each do |card|
      score_meta = card.metadata.to_h.dig('ai', 'score').to_h
      next if score_meta['source'] == 'manual'

      signals = score_meta['signals']
      next if signals.blank?

      apply(card, signals, score_meta['calculated_at'])
    end
  end

  # Card ganho, perdido ou arquivado mantinha a nota e continuava ranqueando como urgente em
  # qualquer consulta que inclua cards fechados. O Evaluator nunca chega neles (só avalia abertos).
  def zero_closed_cards(pipeline)
    pipeline.cards.where.not(status: :open).where('score > 0').find_each do |card|
      card.update!(score: 0)
    end
  end

  # Card sem conversa (criado à mão, importado) não tem "última mensagem" e ficaria congelado para
  # sempre. Nesse caso o relógio corre a partir do momento em que a nota foi calculada.
  def apply(card, signals, calculated_at)
    result = Crm::Ai::ScoreCalculator.new(
      signals: signals,
      last_message_at: last_message_at(card) || parse_time(calculated_at)
    ).perform
    return if result.value == card.score

    metadata = card.metadata.deep_dup
    metadata['ai']['score'] = metadata['ai']['score'].merge(
      'value' => result.value,
      'tier' => result.tier,
      'calculated_at' => Time.current.iso8601
    )
    card.update!(score: result.value, metadata: metadata)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def last_message_at(card)
    ids = ([card.conversation_id] + card.card_conversations.pluck(:conversation_id)).compact.uniq
    Conversation.where(id: ids)
                .filter_map { |conversation| Crm::Conversations::LastRealMessageAt.for(conversation) }
                .max
  end
end
