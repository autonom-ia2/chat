# O que o cliente faz com a reunião pelo link de gestão `/b/<code>` (#1192, J5-A2/A3/A6/A7): confirmar, cancelar,
# remarcar e parar avisos. O convite já foi autorizado pelo controller (código opaco + flag da conta).
#
# - Cancelar e remarcar: só reunião marcada e até `cancel_until_minutes` antes do início (`too_late` depois).
#   Cancelar libera o horário na hora (`CancelService`); os avisos pendentes viram `skipped: 'canceled'`.
# - Remarcar: a MESMA reunião em outro horário, com as regras de horário livre da página (`Slots`, a mesma regra do
#   `Booker`, sem copiar) e sob as mesmas travas, na mesma ordem: caixa da página (1), responsável (2). Conferência
#   com o provedor fora das travas e só a local dentro, como o `Booker`. O horário antigo fica livre no commit.
#   Os avisos vão para o novo horário e a confirmação volta a pendente (é outro horário).
# - Confirmar: idempotente sob trava de linha; confirmar de novo não avisa de novo (J5-A6).
# - Parar avisos: grava a parada do contato (vale para as próximas reuniões), marca as reuniões abertas dele e pula
#   os avisos pendentes; a reunião continua valendo (J5-A7).
#
# Toda ação que muda algo registra atividade no card e avisa o responsável (`Notices::AgentAlert`).
class Crm::BookingV2::ManageMeeting
  def initialize(invite)
    @invite = invite
    @meeting = invite.meeting
  end

  def self.change_deadline(meeting, profile)
    meeting.starts_at - profile.cancel_until_minutes.to_i.minutes
  end

  def confirm!
    confirmed = false
    require_meeting!.with_lock do
      fail!('not_changeable') unless meeting.scheduled? && meeting.starts_at > Time.current
      next if meeting.confirmation_confirmed?

      meeting.update!(confirmation_status: :confirmed, confirmed_at: Time.current)
      confirmed = true
    end
    alert('confirmed') if confirmed
  end

  def cancel!
    canceled = false
    require_meeting!.with_lock do
      ensure_changeable!
      Crm::Meetings::CancelService.new(meeting: meeting).perform
      scheduler.skip_pending!('canceled')
      canceled = true
    end
    alert('canceled') if canceled
  end

  def reschedule!(starts_at:, duration: nil)
    require_meeting!
    ensure_changeable!
    new_start = parse_start(starts_at)
    minutes = resolve_duration(duration)
    previous = meeting.starts_at
    ensure_slot!(new_start, minutes, include_provider: true)
    ActiveRecord::Base.transaction { reschedule_locked!(new_start, minutes) }
    alert('rescheduled', from: previous.iso8601)
  end

  def stop_notices!
    stop = Crm::BookingNoticeStop.create_or_find_by!(account_id: invite.account_id, contact_id: invite.contact_id) do |record|
      record.reason = 'client_link'
    end
    newly = stop.previously_new_record?
    now = Time.current
    open_meetings.where(reminders_stopped_at: nil).update_all(reminders_stopped_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    Crm::MeetingNotice.pending.where(meeting_id: open_meetings.select(:id))
                      .update_all(status: Crm::MeetingNotice.statuses[:skipped], skip_reason: 'stopped', updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    alert('notices_stopped') if newly && meeting.present?
  end

  private

  attr_reader :invite, :meeting

  def profile
    invite.booking_profile
  end

  def scheduler
    Crm::BookingV2::Notices::Scheduler.new(meeting)
  end

  def fail!(code)
    raise Crm::BookingV2::ManageError, code
  end

  def require_meeting!
    fail!('not_changeable') if meeting.blank?
    meeting
  end

  def ensure_changeable!
    fail!('not_changeable') unless meeting.scheduled?
    fail!('too_late') if Time.current >= self.class.change_deadline(meeting, profile)
  end

  def parse_start(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    fail!('slot_unavailable')
  end

  def resolve_duration(value)
    minutes = value.blank? ? ((meeting.ends_at - meeting.starts_at) / 60).round : Integer(value.to_s, exception: false)
    fail!('slot_unavailable') unless profile.durations.include?(minutes)
    minutes
  end

  # Mesma regra de horário livre da página; a própria reunião não conta como ocupada (é ela que muda de lugar).
  def ensure_slot!(start, minutes, include_provider:)
    date = start.in_time_zone(profile.resolved_timezone).to_date.iso8601
    free = Crm::BookingV2::Slots.new(profile: profile, host: meeting.created_by, date: date, duration: minutes, strict: true,
                                     include_provider: include_provider, ignore_meeting_id: meeting.id).perform
    fail!('slot_unavailable') unless free.any? { |iso| Time.iso8601(iso) == start }
  rescue ArgumentError
    fail!('slot_unavailable')
  end

  def reschedule_locked!(start, minutes)
    acquire_locks!
    meeting.lock!
    ensure_changeable!
    ensure_slot!(start, minutes, include_provider: false)
    Crm::Meetings::RescheduleService.new(meeting: meeting, params: { starts_at: start, ends_at: start + minutes.minutes,
                                                                     timezone: meeting.timezone }).perform
    meeting.update!(confirmation_status: :pending, confirmed_at: nil)
    scheduler.reschedule!
  end

  # Mesmas travas e mesma ordem do Booker (caixa da página, depois responsável): remarcar e marcar do mesmo
  # responsável não pegam o mesmo horário.
  def acquire_locks!
    lock!(Crm::BookingV2::Booker::LOCK_NS_INBOX, profile.inbox_id) if profile.inbox_id.present?
    lock!(Crm::BookingV2::Booker::LOCK_NS_AGENT, meeting.created_by_id)
  end

  def lock!(namespace, key)
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{namespace.to_i}, #{key.to_i})")
  end

  def open_meetings
    Crm::Meeting.where(account_id: invite.account_id, status: :scheduled)
                .where(card_id: Crm::Card.where(account_id: invite.account_id, contact_id: invite.contact_id).select(:id))
  end

  def alert(event, payload = {})
    Crm::BookingV2::Notices::AgentAlert.new(meeting.reload, event, payload).perform
  end
end
