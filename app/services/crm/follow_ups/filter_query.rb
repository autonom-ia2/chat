class Crm::FollowUps::FilterQuery
  DEFAULT_INCLUDES = [:card, :series, :company, { conversation: :conversation_participants }, :contact, :inbox, :assignee,
                      :created_by].freeze

  def initialize(scope:, params:, includes: DEFAULT_INCLUDES)
    @scope = scope
    @params = params
    @includes = includes
  end

  def perform
    apply_time_filters(apply_direct_filters(apply_pipeline_filter(base_scope)))
  end

  private

  def base_scope
    @scope.includes(*@includes)
  end

  # Lembrete sem card (#1461) não é de funil nenhum: aparece em qualquer funil escolhido.
  def apply_pipeline_filter(scope)
    return scope if @params[:pipeline_id].blank?

    scope.left_joins(:card).where(crm_cards: { pipeline_id: @params[:pipeline_id] }).or(scope.left_joins(:card).where(card_id: nil))
  end

  def apply_direct_filters(scope)
    filtered_scope = %i[card_id contact_id series_id status inbox_id].reduce(scope) do |current_scope, attribute|
      apply_direct_filter(current_scope, attribute)
    end

    apply_assignee_filter(filtered_scope)
  end

  def apply_direct_filter(scope, attribute)
    return scope if @params[attribute].blank?

    scope.where(attribute => @params[attribute])
  end

  def apply_assignee_filter(scope)
    assignee_id = @params[:assignee_id].presence || @params[:owner_id].presence
    return scope if assignee_id.blank?

    scope.where(assignee_id: assignee_id)
  end

  def apply_time_filters(scope)
    apply_to_filter(apply_from_filter(scope))
  end

  def apply_from_filter(scope)
    return scope if parsed_time(:from).blank?

    scope.where('crm_follow_ups.due_at >= ?', parsed_time(:from))
  end

  def apply_to_filter(scope)
    return scope if parsed_time(:to).blank?

    scope.where('crm_follow_ups.due_at <= ?', parsed_time(:to))
  end

  def parsed_time(key)
    @parsed_time ||= {}
    @parsed_time[key] ||= safe_time(@params[key]) if @params[key].present?
  rescue ArgumentError, TypeError
    @parsed_time[key] = nil
  end

  def safe_time(raw_value)
    parsed_value = Time.zone.parse(raw_value)
    return if parsed_value.blank?
    return unless parsed_value.year.between?(1900, 9999)

    parsed_value
  end
end
