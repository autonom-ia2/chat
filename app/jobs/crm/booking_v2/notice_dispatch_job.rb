# Cron de avisos do agendamento (#1192, PLANO §2.5/§8), a cada minuto em `scheduled_jobs`.
#
# Sai sem consultar nada se o calendário de reuniões da instalação estiver desligado. Senão, 1 SELECT pelo índice
# (status, due_at) com LIMIT 200 e, para cada aviso vencido, um claim atômico
# (`UPDATE ... SET status = sending WHERE id = ? AND status = pending`): duas execuções ao mesmo tempo nunca mandam o
# mesmo aviso duas vezes. A flag da conta é conferida no envio (`Notices::Sender`), que é o kill-switch por conta.
#
# Aviso preso em `sending` por mais de STALE_AFTER (processo morto no meio do envio) vira `failed: interrupted` sem
# reenviar: não sabemos se saiu, e mandar duas vezes é pior do que não mandar.
class Crm::BookingV2::NoticeDispatchJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH = 200
  STALE_AFTER = 15.minutes

  def perform
    return unless Crm::Config.calendar_meetings_enabled?

    fail_stale!
    due_ids.each { |id| dispatch(id) }
  end

  private

  def due_ids
    Crm::MeetingNotice.pending.where('due_at <= ?', Time.current).order(:due_at).limit(BATCH).pluck(:id)
  end

  def claim(id)
    Crm::MeetingNotice.where(id: id, status: :pending)
                      .update_all(['status = ?, attempts = attempts + 1, updated_at = ?', Crm::MeetingNotice.statuses[:sending], Time.current]) # rubocop:disable Rails/SkipsModelValidations
                      .positive?
  end

  # Um aviso com problema não para os outros: o erro fica registrado no aviso e no log.
  def dispatch(id)
    return unless claim(id)

    Crm::BookingV2::Notices::Sender.new(Crm::MeetingNotice.includes(meeting: [:account, { card: :contact }]).find(id)).perform
  rescue StandardError => e
    Rails.logger.error("CRM booking notice dispatch #{id} failed: #{e.class.name}")
    Crm::MeetingNotice.where(id: id, status: :sending).update_all(status: Crm::MeetingNotice.statuses[:failed], error_code: e.class.name.first(255)) # rubocop:disable Rails/SkipsModelValidations
  end

  def fail_stale!
    Crm::MeetingNotice.sending.where('updated_at < ?', STALE_AFTER.ago)
                      .update_all(status: Crm::MeetingNotice.statuses[:failed], error_code: 'interrupted', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
