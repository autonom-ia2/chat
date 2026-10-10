# Agenda os avisos de uma reunião do agendamento (#1192, J5-A1/A8). Só para reunião de página nova cuja página tem
# caixa de avisos utilizável.
#
# - `schedule!(invite:)` (ao marcar): uma linha por aviso do jogo da página (`booked` vence agora; os lembretes no
#   horário deles). Lembrete cujo horário já passou não é criado, nem o que cairia a menos de MIN_GAP de outro aviso
#   da reunião (ex.: marcar 1h10 antes não manda "1 hora antes" 10 minutos depois do "marcado"). Repetir não duplica
#   (único por reunião e aviso). A reunião guarda a conversa do convite e, se o contato já parou os avisos, nasce com
#   eles parados.
# - `reschedule!` (remarcar): `rescheduled` vence agora e os lembretes vão para o novo horário. Linhas de volta a
#   pendente, menos a que está saindo agora (`sending`); lembrete que ficou no passado vira `skipped: 'past_due'`; o
#   que cairia perto demais de outro vira `skipped: 'too_close'`; `booked` ainda pendente vira `skipped: 'replaced'`.
# - `Scheduler.meeting_moved!(meeting)`: chamado pelo `Crm::Meetings::RescheduleService` em toda mudança de horário
#   (cliente, painel ou agenda do provedor). Reunião de página nova: a confirmação volta a pendente (o cliente
#   confirmou outro horário; o "remarcado" leva o link para confirmar de novo) e os avisos são reprogramados.
# - `skip_pending!(reason)` (cancelar, parar avisos): pendentes viram `skipped` com o motivo.
class Crm::BookingV2::Notices::Scheduler
  OFFSETS = { 'day_before' => 1.day, 'hour_before' => 1.hour }.freeze
  # Folga mínima entre dois avisos da mesma reunião.
  MIN_GAP = 30.minutes
  # `sent_at` fica: é o que conta no teto por número (o aviso saiu, mesmo que vá sair de novo no novo horário).
  RESET = { status: :pending, skip_reason: nil, error_code: nil, message_id: nil, attempts: 0 }.freeze

  def self.profile_for(meeting)
    id = meeting.metadata.to_h['booking_profile_id']
    return if id.blank?

    Crm::AgentBookingProfile.new_pages.find_by(id: id, account_id: meeting.account_id)
  end

  def self.meeting_moved!(meeting)
    return if profile_for(meeting).blank?

    meeting.update!(confirmation_status: :pending, confirmed_at: nil) unless meeting.confirmation_pending?
    new(meeting).reschedule!
  end

  # Horário certo de um aviso (lembrete: início menos a antecedência; os outros: agora).
  def self.expected_due_at(meeting, kind, now = Time.current)
    offset = OFFSETS[kind.to_s]
    offset ? meeting.starts_at - offset : now
  end

  def initialize(meeting)
    @meeting = meeting
  end

  def schedule!(invite: nil)
    return unless active?

    remember_context!(invite)
    plan = kinds.index_with { |kind| due_at(kind) }
    rows = plan.except(*too_close_kinds(plan, Time.current)).filter_map { |kind, due| row(kind, due) }
    Crm::MeetingNotice.insert_all(rows, unique_by: %i[meeting_id kind]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def reschedule!
    return unless active?

    now = Time.current
    # O "marcado" que ainda não saiu falaria do horário antigo: o "remarcado" o substitui.
    meeting.notices.pending.where(kind: 'booked').update_all(status: Crm::MeetingNotice.statuses[:skipped], skip_reason: 'replaced', updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    plan = { 'rescheduled' => now }.merge(kinds.excluding('booked').index_with { |kind| due_at(kind) })
    close = too_close_kinds(plan, now)
    plan.each { |kind, due| close.include?(kind) ? drop!(kind, 'too_close') : rearm!(kind, due, now) }
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
    self.class.expected_due_at(meeting, kind)
  end

  # Avisos do plano ({ aviso => vencimento }, na ordem: o imediato primeiro) que cairiam a menos de MIN_GAP de um
  # aviso já mantido. O que já passou fica de fora da conta (vira `past_due`).
  def too_close_kinds(plan, now)
    kept = []
    plan.filter_map do |kind, due|
      next if past?(due, now)
      next kind if kept.any? { |other| (other - due).abs < MIN_GAP }

      kept << due
      nil
    end
  end

  def past?(due, now)
    due < 1.minute.before(now)
  end

  def row(kind, due)
    return if past?(due, Time.current)

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
    return existing&.update!(status: :skipped, skip_reason: 'past_due') if past?(due, now)

    return existing.update!(RESET.merge(due_at: due)) if existing

    meeting.notices.create!(account_id: meeting.account_id, kind: kind, due_at: due)
  end

  def drop!(kind, reason)
    existing = meeting.notices.find_by(kind: kind)
    return if existing.nil? || existing.sending?

    existing.update!(status: :skipped, skip_reason: reason)
  end
end
