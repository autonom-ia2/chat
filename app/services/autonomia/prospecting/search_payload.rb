# A busca como a API devolve (listar, abrir, criar e mudar a busca). Saiu do controller no #2693, que precisou mexer nele;
# a ordem das chaves é a de antes, e o retrato do motor legado (spec/support/prospecting_payload_snapshot.rb) confere o
# JSON byte a byte. `leads` são os leads da busca já carregados, na ordem dela.
class Autonomia::Prospecting::SearchPayload
  ATTRIBUTES = [
    :id, :query, :location, :radius, :area_type, :area_config, :provider, :status, :requested_limit, :created_at, :updated_at
  ].freeze
  CRM_KEYS = %w[crm_pipeline_id crm_stage_id].freeze
  LOCATION_KEYS = %w[location_place_id location_latitude location_longitude location_label].freeze
  SCORING_KEYS = %w[score_mode scoring_profile_id preset_id].freeze
  SUMMARY_COUNT_KEYS = %w[results_count contact_count crm_count ready_count average_score].freeze

  # Posição e nota do lead nesta busca (#677, #678), guardadas nela, no mesmo formato do atributo do lead. Busca anterior
  # a isso não tem: ficam os valores do lead.
  def self.lead_in_search(lead, search)
    metadata = search&.metadata.to_h
    rank = metadata.dig('lead_ranks', lead.id.to_s)
    scoring = metadata.dig('lead_scoring', lead.id.to_s)
    (rank.nil? ? {} : { 'search_rank' => rank }).merge(lead_scoring(scoring))
  end

  def self.lead_scoring(scoring)
    return {} if scoring.blank?

    scoring.slice('score', 'score_breakdown', 'priority_score', 'priority_position').to_h do |key, value|
      [key, Autonomia::Prospecting::Lead.type_for_attribute(key).cast(value).as_json]
    end
  end

  def initialize(search:, leads:)
    @search = search
    @leads = leads
    @metadata = search.metadata.to_h
  end

  def build
    counts = lead_counts
    @search.as_json(only: ATTRIBUTES)
           .merge({ 'results_count' => counts['results_count'], 'requested_radius' => requested_radius })
           .merge(metadata_values(CRM_KEYS), counts.except('results_count'), metadata_values(LOCATION_KEYS), filters, author)
           .merge(metadata_values(SCORING_KEYS), { 'decision_maker_type' => decision_maker_type })
           .merge({ 'summary' => summary(counts), 'research_progress' => Autonomia::Prospecting::Research::Queue.progress(@leads) })
  end

  private

  def lead_counts
    {
      'results_count' => results_count,
      'crm_count' => @leads.count { |lead| lead.crm_card_id.present? },
      'contact_count' => @leads.count { |lead| lead.contact_id.present? },
      'average_score' => average_score,
      'ready_count' => @leads.count { |lead| lead.status == 'ready_for_campaign' }
    }
  end

  def results_count
    return @metadata['results_count'] if @metadata.key?('results_count')

    lead_ids = Array(@metadata['lead_ids'])
    lead_ids.present? ? lead_ids.size : @leads.count
  end

  def average_score
    scored_leads = @leads.filter { |lead| lead.score.present? }
    return if scored_leads.blank?

    (scored_leads.sum { |lead| lead.score.to_f } / scored_leads.size).round(1)
  end

  # Raio pedido, para repetir a busca (#678): com "Expandir raio", radius é o que a expansão alcançou.
  def requested_radius
    @metadata['requested_radius'] || @search.radius
  end

  def filters
    {
      'search_filters' => @metadata['search_filters'] || @metadata['filters'] || {},
      'advanced_filters' => @metadata['advanced_filters'] || {},
      'sort_key' => @metadata['sort_key']
    }
  end

  # Quem fez a busca (#2693): a tela mostra "Feita por" e só oferece "Apagar" na busca da própria pessoa.
  def author
    { 'user_id' => @search.user_id, 'user_name' => @search.user&.name }
  end

  def decision_maker_type
    @metadata['decision_maker_type'].presence || Autonomia::Prospecting::DecisionMakerType::DEFAULT
  end

  def summary(counts)
    counts.slice(*SUMMARY_COUNT_KEYS).transform_keys(&:to_sym).merge(
      consumed_api_units: @search.consumed_api_units.to_i,
      radius_expanded: ActiveModel::Type::Boolean.new.cast(@metadata['radius_expanded']),
      cached_from_search_id: @metadata['cached_from_search_id'],
      partial_results: @metadata['partial_results'] == true
    )
  end

  def metadata_values(keys)
    keys.index_with { |key| @metadata[key] }
  end
end
