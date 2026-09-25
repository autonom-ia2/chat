# Nota do Orth dos leads de uma busca (#681): monta a entrada da fórmula (frente A) com os sinais que o lead já tem e dá a
# posição na fila "Ligar 1º" pela prioridade do Orth. A coorte da nota é a própria busca. Não grava nada.
class Autonomia::Prospecting::Scoring::OrthRanking
  Scoring = Autonomia::Prospecting::Scoring
  # Decisor procurado e não achado conta como tentativa sem nome (decisorFailed do Orth). Falha técnica não diz nada do
  # lead e fica como pendente.
  DECISOR_NOT_FOUND = %w[no_result ambiguous].freeze

  Entry = Struct.new(:lead, :result, :priority_position, keyword_init: true) do
    # O que a busca guarda em lead_scoring[id]['orth'].
    def summary
      { 'score' => result.score, 'priority_score' => result.priority_score, 'band' => Scoring::Band.code(result.priority_score),
        'human_insight' => result.human_insight }
    end

    # As colunas que o lead mostra quando a conta está no motor do Orth, no formato que a tela já lê.
    def lead_columns(mode)
      { score: result.score, priority_score: result.priority_score, priority_position: priority_position,
        score_breakdown: breakdown(mode), negative_factors: Array(result.negative_factors), human_insight: result.human_insight }
    end

    def breakdown(mode)
      Array(result.components).to_h do |component|
        component = component.to_h.stringify_keys
        [component['key'].to_s, { 'signal' => component['value'], 'weight' => component['weight'],
                                  'weighted_score' => component['points'], 'audit' => component['audit'] }]
      end.merge('_engine' => 'orth', '_mode' => mode, '_total' => result.score,
                '_effective_weights' => result.effective_weights.to_h.stringify_keys)
    end
  end

  def initialize(leads:, mode:, weights:, filters:)
    @leads = leads
    @mode = mode
    @weights = weights
    @filters = filters
  end

  def perform
    results = Scoring::OrthScorer.new(leads: @leads.map { |lead| input(lead) }, mode: @mode, weights: @weights, filters: @filters).perform
    raise ArgumentError, "OrthScorer devolveu #{results.size} notas para #{@leads.size} leads" unless results.size == @leads.size

    entries = @leads.zip(results).map { |lead, result| Entry.new(lead: lead, result: result) }
    positioned(entries)
  end

  private

  # Mesmo desempate da prioridade legada: nota, posição no Google e nome.
  def positioned(entries)
    order = entries.sort_by do |entry|
      rank = entry.lead.search_rank.to_i
      [-entry.result.priority_score.to_f, -entry.result.score.to_f, rank.positive? ? rank : Float::INFINITY, entry.lead.name.to_s]
    end
    order.each_with_index { |entry, index| entry.priority_position = index + 1 }
    entries
  end

  def input(lead)
    raw = lead.raw_payload.to_h
    {
      name: lead.name, website: lead.website, phone: lead.phone, rating: lead.rating&.to_f, reviews_count: lead.reviews_count,
      reviews: Array(raw['reviews']).map { |review| { publish_time: review.to_h['publishTime'] } }, search_rank: lead.search_rank
    }.merge(place_signals(lead, raw)).merge(action_signals(lead)).with_indifferent_access
  end

  # Fotos e aberto agora: a coluna que o provider grava desde a E1; lead gravado antes dela usa o payload do Google.
  def place_signals(lead, raw)
    photos = Array(raw['photos'])
    {
      photo_count: lead.photo_count || photos.size,
      has_photos: lead.has_photos.nil? ? photos.any? : lead.has_photos,
      open_now: lead.open_now.nil? ? raw.dig('currentOpeningHours', 'openNow') == true : lead.open_now
    }
  end

  # Contato e decisor da prioridade do Orth (priority-score.ts), lidos do mesmo lugar que a prioridade legada.
  def action_signals(lead)
    {
      whatsapp_verified: lead.metadata.to_h.dig('whatsapp_verification', 'status') == 'verified',
      decisor_found: lead.decision_name.present? &&
        Autonomia::Prospecting::Research::Payload::FOUND.include?(lead.decision_research_status),
      decisor_failed: DECISOR_NOT_FOUND.include?(lead.decision_research_status)
    }
  end
end
