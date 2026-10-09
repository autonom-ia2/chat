# Agenda os avisos de uma reunião do agendamento (#1192, J5-A1/A8). Só para reunião de página nova cuja página tem
# caixa de avisos utilizável.
#
# - `schedule!(invite:)` (ao marcar): uma linha por aviso do jogo da página (`booked` vence agora; os lembretes no
#   horário deles). Lembrete cujo horário já passou não é criado. Repetir não duplica (único por reunião e aviso).
#   A reunião guarda a conversa do convite e, se o contato já parou os avisos, nasce com eles parados.
# - `reschedule!` (remarcar): `rescheduled` vence agora e os lembretes vão para o novo horário. Linhas de volta a
#   pendente, menos a que está saindo agora (`sending`); lembrete que ficou no passado vira `skipped: 'past_due'`;
#   `booked` ainda pendente vira `skipped: 'replaced'`.
# - `skip_pending!(reason)` (cancelar, parar avisos): pendentes viram `skipped` com o motivo.
class Crm::BookingV2::Notices::Scheduler
  OFFSETS = { 'day_before' => 1.day, 'hour_before' => 1.hour }.freeze
  # `sent_at` fica: é o que conta no teto por número (o aviso saiu, mesmo que vá sair de novo no novo horário).
  RESET = { status: :pending, skip_reason: nil, error_code: nil, message_id: nil, attempts: 0 }.freeze

  def self.profile_for(meeting)
    id = meeting.metadata.to_h['booking_profile_id']
    return if id.blank?

    Crm::AgentBookingProfile.new_pages.find_by(id: id, account_id: meeting.account_id)
  end

  def initialize(meeting)
    @meeting = meeting
  end

  def schedule!(invite: nil)
    return unless active?

    remember_context!(invite)
    rows = kinds.filter_map { |kind| row(kind, due_at(kind)) }
    Crm::MeetingNotice.insert_all(rows, unique_by: %i[meeting_id kind]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def reschedule!
    return unless active?

    now = Time.current
    # O "marcado" que ainda não saiu falaria do horário antigo: o "remarcado" o substitui.
    meeting.notices.pending.where(kind: 'booked').update_all(status: Crm::MeetingNotice.statuses[:skipped], skip_reason: 'replaced', updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    (['rescheduled'] + kinds.excluding('booked')).each { |kind| rearm!(kind, kind == 'rescheduled' ? now : due_at(kind), now) }
  end

  def skip_pending!(reason)
    meeting.notices.pending.update_all(status: Crm::MeetingNotice.statuses[:skipped], skip_reason: reason, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  attr_reader :meeting

  def profile
    return @profile if defined?(@profile)

    @profile = self.class.profile_for(meeting)
  end

  def active?
    meeting.scheduled? && profile&.notices_usable? && Crm::Config.booking_v2_enabled?(meeting.account)
  end

  def kinds
    profile.notice_kinds
  end

  def due_at(kind)
    offset = OFFSETS[kind]
    offset ? meeting.starts_at - offset : Time.current
  end

  def row(kind, due)
    return if due < 1.minute.ago

    now = Time.current
    { meeting_id: meeting.id, account_id: meeting.account_id, kind: kind, due_at: due, status: Crm::MeetingNotice.statuses[:pending],
      created_at: now, updated_at: now }
  end

  def remember_context!(invite)
    changes = {}
    changes[:conversation_id] = invite.conversation_id if meeting.conversation_id.blank? && invite&.conversation_id.present?
    changes[:reminders_stopped_at] = Time.current if meeting.reminders_stopped_at.blank? && contact_stopped?
    meeting.update!(changes) if changes.any?
  end

  def contact_stopped?
    Crm::BookingNoticeStop.stopped?(account_id: meeting.account_id, contact_id: meeting.card.contact_id)
  end

  def rearm!(kind, due, now)
    existing = meeting.notices.find_by(kind: kind)
    return if existing&.sending?
    return existing&.update!(status: :skipped, skip_reason: 'past_due') if due < 1.minute.before(now)

    return existing.update!(RESET.merge(due_at: due)) if existing

    meeting.notices.create!(account_id: meeting.account_id, kind: kind, due_at: due)
  end
end
