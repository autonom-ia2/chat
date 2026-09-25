# Prioridade "ligar primeiro" dentro de uma busca (porte de computeRawPriority e rankByPriority do priority-score.ts do
# Orth, #681). Bruta = nota × contato × decisor × aberto agora − penalidade; depois vira percentil entre os leads da
# busca (topo 100, fundo 0, empate nivela por cima) e posição 1..N, desempatando por nota e por posição no Google.
module Autonomia::Prospecting::Scoring::Priority
  CONTACT_WHATSAPP = 1.3
  CONTACT_PHONE_ONLY = 1.0
  CONTACT_NONE = 0.3
  DECISOR_FOUND = 1.2
  DECISOR_PENDING = 1.0
  DECISOR_FAILED = 0.8
  HOUR_OPEN = 1.15
  HOUR_DEFAULT = 1.0

  module_function

  # O bônus de aberto agora não vale com o filtro de aberto agora ligado: todos da busca já estão abertos.
  def factors(base_score:, signals:, negative_penalty:, open_now_filter_active: false)
    contactability = contactability(signals)
    decisor = decisor(signals)
    hour = !open_now_filter_active && signals.open_now ? HOUR_OPEN : HOUR_DEFAULT
    raw_multiplier = contactability * decisor * hour

    { contactability: contactability, decisor: decisor, hour: hour, raw_multiplier: raw_multiplier,
      raw_priority: (base_score * raw_multiplier) - negative_penalty }
  end

  def contactability(signals)
    return CONTACT_WHATSAPP if signals.whatsapp_verified
    return CONTACT_PHONE_ONLY if signals.phone?

    CONTACT_NONE
  end

  def decisor(signals)
    return DECISOR_FOUND if signals.decisor_found
    return DECISOR_FAILED if signals.decisor_failed

    DECISOR_PENDING
  end

  # Devolve, na ordem de entrada, os fatores, a prioridade de 0 a 100 e a posição de cada lead.
  def rank(inputs)
    return [] if inputs.empty?

    scored = inputs.map { |input| factors(**input) }
    percentiles = percentiles(scored.pluck(:raw_priority))
    ranked = scored.map do |item|
      { factors: item, priority_score: (percentiles.fetch(item[:raw_priority]) * 100).round.clamp(0, 100) }
    end
    positions = positions(inputs, ranked)
    ranked.each_with_index.map { |item, index| item.merge(priority_position: positions.fetch(index)) }
  end

  def percentiles(raw_priorities)
    sorted = raw_priorities.sort
    return { sorted.first => 1.0 } if sorted.one?

    sorted.each_with_index.with_object({}) do |(raw, index), memo|
      percentile = index.to_f / (sorted.size - 1)
      memo[raw] = percentile if memo[raw].nil? || percentile > memo[raw]
    end
  end

  def positions(inputs, ranked)
    order = ranked.each_index.sort_by do |index|
      rank = inputs[index][:signals].search_rank
      [-ranked[index][:priority_score], -inputs[index][:base_score], rank || Float::INFINITY, index]
    end
    order.each_with_index.to_h { |index, position| [index, position + 1] }
  end
end
