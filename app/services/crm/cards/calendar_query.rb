class Crm::Cards::CalendarQuery
  def initialize(scope:, params:)
    @scope = scope
    @params = params
  end

  def perform
    apply_time_filters(apply_direct_filters(base_scope))
  end

  private

  def base_scope
    @scope.includes(primary_conversation: :conversation_participants)
  end

  def apply_direct_filters(scope)
    scope = scope.where(pipeline_id: @params[:pipeline_id]) if @params[:pipeline_id].present?
    scope = scope.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
    scope = scope.where(owner_id: owner_id) if owner_id.present?
    scope
  end

  def owner_id
    @params[:owner_id].presence || @params[:assignee_id].presence
  end

  # O vencimento é uma data gravada como 00:00 UTC (#1538): a janela vem em instantes do fuso de quem olha, então o
  # filtro compara pelo dia UTC. Sem isso o vencimento do primeiro dia da janela ficava de fora a oeste de UTC.
  def apply_time_filters(scope)
    scope = scope.where('crm_cards.expected_close_at >= ?', parsed_time(:from).utc.beginning_of_day) if parsed_time(:from).present?
    scope = scope.where('crm_cards.expected_close_at <= ?', parsed_time(:to).utc.end_of_day) if parsed_time(:to).present?
    scope
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
