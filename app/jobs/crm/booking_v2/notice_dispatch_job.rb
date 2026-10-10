# Cron de avisos do agendamento (#1192, PLANO §2.5/§8), a cada minuto em `scheduled_jobs`.
#
# Sai sem consultar nada se o calendário de reuniões da instalação estiver desligado. Senão, 1 SELECT pelo índice
# (status, due_at) com LIMIT 200 e, para cada aviso vencido, um claim atômico
# (`UPDATE ... SET status = sending WHERE id = ? AND status = pending`): duas execuções ao mesmo tempo nunca mandam o
# mesmo aviso duas vezes. A flag da conta é conferida no envio (`Notices::Sender`), que é o kill-switch por conta.
#
# Falhas, todas avisando o responsável (uma vez por reunião, `Notices::AgentAlert`):
# - aviso preso em `sending` por mais de STALE_AFTER (processo morto no meio do envio) vira `failed: interrupted` sem
#   reenviar: não sabemos se saiu, e mandar duas vezes é pior do que não mandar;
# - erro inesperado no envio vira `failed` com a classe do erro (log + tracker);
# - `sent` quer dizer mensagem criada, não entregue: aviso enviado nas últimas DELIVERY_CHECK cuja mensagem o
#   provedor marcou depois como `failed` vira `failed: delivery_failed` (1 SELECT pelo mesmo índice, LIMIT 200).
class Crm::BookingV2::NoticeDispatchJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH = 200
  STALE_AFTER = 15.minutes
  DELIVERY_CHECK = 2.hours
  # Limite do índice (status, due_at) na conferência de entrega: o aviso sai no minuto em que vence, então quem saiu
  # nas últimas DELIVERY_CHECK venceu há bem menos que isso mais um dia.
  DELIVERY_DUE_WINDOW = DELIVERY_CHECK + 1.day

  def perform
    return unless Crm::Config.calendar_meetings_enabled?

    fail_stale!
    fail_undelivered!
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

  # Um aviso com problema não para os outros: o erro fica registrado no aviso, no log e no tracker.
  def dispatch(id)
    return unless claim(id)

    Crm::BookingV2::Notices::Sender.new(Crm::MeetingNotice.includes(meeting: [:account, { card: :contact }]).find(id)).perform
  rescue StandardError => e
    Rails.logger.error("CRM booking notice dispatch #{id} failed: #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: Crm::MeetingNotice.find_by(id: id)&.account).capture_exception
    fail!(id, from: :sending, code: e.class.name.first(255))
  end

  def fail_stale!
    Crm::MeetingNotice.sending.where('updated_at < ?', STALE_AFTER.ago).limit(BATCH).pluck(:id)
                      .each { |id| fail!(id, from: :sending, code: 'interrupted') }
  end

  def fail_undelivered!
    since = DELIVERY_CHECK.ago
    Crm::MeetingNotice.sent.where('crm_meeting_notices.due_at > ?', DELIVERY_DUE_WINDOW.ago)
                      .where('crm_meeting_notices.sent_at > ?', since)
                      .joins('INNER JOIN messages ON messages.id = crm_meeting_notices.message_id')
                      .where(messages: { status: Message.statuses[:failed] })
                      .limit(BATCH).pluck(:id)
                      .each { |id| fail!(id, from: :sent, code: 'delivery_failed') }
  end

  # Muda só se o aviso ainda está no estado esperado (outro processo pode ter mexido) e, mudando, avisa o responsável.
  def fail!(id, from:, code:)
    changed = Crm::MeetingNotice.where(id: id, status: from)
                                .update_all(status: Crm::MeetingNotice.statuses[:failed], error_code: code, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    alert_failure(id, code) if changed.positive?
  end

  # Falhar o aviso ao responsável não pode derrubar o cron: o erro vai ao log e ao tracker e o cron segue.
  def alert_failure(id, code)
    notice = Crm::MeetingNotice.includes(meeting: [:account, { card: :contact }]).find(id)
    Crm::BookingV2::Notices::AgentAlert.new(notice.meeting, 'notice_failed', { kind: notice.kind, reason: code }).perform
  rescue StandardError => e
    Rails.logger.error("CRM booking notice alert #{id} failed: #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: notice&.account).capture_exception
  end
end
