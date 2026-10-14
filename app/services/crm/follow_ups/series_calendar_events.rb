# #1460 — as vezes futuras de cada lembrete que repete, para o calendário. Só a próxima vez existe em crm_follow_ups
# (SeriesMaterializer); as seguintes são calculadas aqui, a partir da última vez criada, dentro da janela pedida.
# Série pausada continua mostrando as datas, marcadas como pausadas (decisão do Rodrigo, 14/10/2026).
class Crm::FollowUps::SeriesCalendarEvents
  def initialize(scope:, from:, to:, pipeline_id: nil)
    @scope = scope
    @from = from
    @to = to
    @pipeline_id = pipeline_id
  end

  # Um lembrete do calendário; a vez de uma série leva a série junto (#1460).
  def self.follow_up_event(follow_up, conversation_id:)
    {
      id: "follow_up_#{follow_up.id}", event_type: "follow_up_#{follow_up.automation_mode}", title: follow_up.title,
      starts_at: follow_up.due_at&.iso8601, status: follow_up.status, card_id: follow_up.card_id,
      conversation_id: conversation_id, contact_id: follow_up.contact_id, inbox_id: follow_up.inbox_id,
      assignee_id: follow_up.assignee_id, series_id: follow_up.series_id, series_status: follow_up.series&.status,
      recurring: follow_up.series_id.present?
    }
  end

  def events
    return [] if @from.blank? || @to.blank?

    series = series_in_view
    @last_occurrences = Crm::FollowUp.where(series_id: series.map(&:id)).group(:series_id).maximum(:occurrence_at)
    series.flat_map { |item| events_for(item) }
  end

  private

  def series_in_view
    scope = @scope.where(status: %i[active paused]).includes(:card)
    return scope.to_a if @pipeline_id.blank?

    joined = scope.left_joins(:card)
    joined.where(crm_cards: { pipeline_id: @pipeline_id }).or(joined.where(card_id: nil)).to_a
  end

  def events_for(series)
    last = @last_occurrences[series.id]
    series.schedule.between(@from, @to).reject { |occurrence| last && occurrence <= last }.map do |occurrence|
      event(series, occurrence)
    end
  end

  def event(series, occurrence)
    {
      id: "follow_up_series_#{series.id}_#{occurrence.to_i}",
      event_type: 'follow_up_reminder_only',
      title: series.title,
      starts_at: occurrence.iso8601,
      status: series.paused? ? 'paused' : 'pending',
      card_id: series.card_id,
      contact_id: series.contact_id || series.card&.contact_id,
      series_id: series.id,
      series_status: series.status,
      recurring: true,
      virtual: true
    }
  end
end
