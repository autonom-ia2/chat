class Crm::Meetings::RecordOutcomeService
  VALID_OUTCOMES = %w[held no_show].freeze
  MAX_NOTES_LENGTH = 5000
  # Marca, em metadata, o primeiro "Aconteceu" (#1193): a oferta de mover o card sai uma vez só.
  POST_MEETING_MARK = 'post_meeting_at'.freeze

  # `post_meeting`: o que fazer com o card depois de "Aconteceu" numa reunião de página de agendamento (#1193, J4-A7),
  # vindo do `Crm::BookingV2::PostMeeting`; nil quando não há nada a oferecer. `actor`: quem registrou (move o card em
  # `auto`); sem ele, o responsável da reunião.
  attr_reader :post_meeting

  def initialize(meeting:, outcome:, notes: nil, actor: nil)
    @meeting = meeting
    @outcome = outcome.to_s
    @notes = notes
    @actor = actor
  end

  def perform
    raise ArgumentError, 'invalid_outcome' unless VALID_OUTCOMES.include?(@outcome)
    # Outcome is CRM-internal (no calendar-provider call), so it is provider
    # agnostic and behaves identically for Google and Microsoft meetings.
    raise ArgumentError, 'meeting_not_active' unless @meeting.scheduled?
    # Server-side guard: an outcome can only be recorded after the meeting has
    # actually finished. The FE hides the prompt for future meetings, but the
    # API must enforce it too (no marking a next-week meeting as no-show today).
    raise ArgumentError, 'meeting_not_finished' unless @meeting.ends_at.present? && @meeting.ends_at <= Time.current

    first_held = save_outcome!

    log_activity
    offer_post_meeting if first_held
    @meeting
  end

  private

  # Grava o resultado sob trava na reunião e diz se este é o primeiro "Aconteceu" dela. Dois toques ao mesmo tempo:
  # o segundo espera e já vê o primeiro, então o card não é movido duas vezes.
  def save_outcome!
    first_held = false
    @meeting.with_lock do
      first_held = first_held?
      attributes = { outcome: @outcome, outcome_notes: sanitized_notes, outcome_recorded_at: Time.current }
      attributes[:metadata] = @meeting.metadata.to_h.merge(POST_MEETING_MARK => Time.current.iso8601) if first_held
      @meeting.update!(attributes)
    end
    first_held
  end

  # Só uma vez por reunião: salvar as anotações de uma reunião que já "Aconteceu" passa por aqui de novo, e trocar
  # para "Não compareceu" e voltar para "Aconteceu" não oferece (nem move) outra vez.
  def first_held?
    @outcome == 'held' && !@meeting.outcome_held? && @meeting.metadata.to_h[POST_MEETING_MARK].blank?
  end

  def offer_post_meeting
    @post_meeting = Crm::BookingV2::PostMeeting.new(meeting: @meeting, actor: @actor || @meeting.created_by).perform
  end

  def sanitized_notes
    return if @notes.blank?

    # Strip HTML tags + control chars (defense-in-depth, mirrors the meeting
    # description sanitizer) before storing — notes are shown in the card and
    # later fed to the AI summary (S5).
    ActionController::Base.helpers.strip_tags(@notes.to_s)
                          .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, '')
                          .strip.truncate(MAX_NOTES_LENGTH)
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: @meeting.card,
      actor: @meeting.created_by,
      event_type: 'meeting_outcome_recorded',
      conversation: @meeting.card.primary_conversation,
      payload: {
        meeting_id: @meeting.id,
        outcome: @meeting.outcome,
        title: @meeting.title
      }
    ).perform
  end
end
