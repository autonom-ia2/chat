# Pesos de 8 sinais de hoje (perfil do catálogo ou customizado da conta) para os 6 componentes do Orth (#681, decisão
# do Rodrigo de 25/09: pesos próprios ficam, mapeados). reviews_count vira volume; google_rank e query_relevance saem,
# porque no Orth a posição no Google é a tração e a relevância da consulta não existe. O resto volta a somar 100 como no
# normalizeWeights do effective-weights.ts: arredonda cada um e a sobra vai para o site.
module Autonomia::Prospecting::Scoring::WeightMapping
  LEGACY_KEYS = {
    'website' => 'website',
    'phone' => 'phone',
    'rating' => 'rating',
    'volume' => 'reviews_count',
    'activity' => 'activity',
    'photos' => 'photos'
  }.freeze

  module_function

  def from_legacy(weights)
    legacy = Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.merge(weights.to_h.stringify_keys)
    mapped = LEGACY_KEYS.transform_values { |legacy_key| legacy.fetch(legacy_key).to_f }
    total = mapped.values.sum
    return Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT.dup if total <= 0

    normalized = mapped.transform_values { |value| (value * 100 / total).round }
    normalized.merge('website' => normalized['website'] + 100 - normalized.values.sum)
  end
end
