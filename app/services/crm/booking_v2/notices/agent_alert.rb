# Registra no card e avisa o responsável sobre o que o cliente fez na página de gestão e sobre aviso que não saiu
# (#1192, J5-A3/A4/A6, RA-19).
#
# - Atividade no card SEMPRE (é o registro para medição, RA-19): `booking_client_confirmed`,
#   `booking_client_canceled`, `booking_client_rescheduled`, `booking_client_rebooked` (marcou de novo pelo link depois de
#   uma reunião cancelada), `booking_notice_failed`, `booking_notices_stopped`.
#   `by`: 'client' no que o cliente fez pela página de gestão; 'system' no aviso que não saiu.
# - Aviso ao responsável pelo caminho que o CRM já usa para chamar a pessoa: uma tarefa vencendo agora
#   (`Crm::FollowUp`, lembrete), que o cron de tarefas transforma em push/e-mail conforme as preferências dela e que
#   aparece no aviso de tarefas do painel. Parar avisos só registra. Aviso que não saiu avisa UMA vez por reunião.
#   O `metadata` leva o que o cartão do painel precisa para dizer o que houve sem parecer tarefa atrasada (#1291):
#   `source`, `event`, o cliente, o horário e, no aviso que não saiu, o tipo do aviso e o motivo.
# - `notice_stop_failed` (#1562): o aviso saiu, mas a mensagem 2 com o botão "Parar avisos" não. Mesma atividade do
#   aviso que não saiu (`booking_notice_failed`, motivo `stop_part_failed`) e título próprio. Avisa UMA vez por AVISO
#   ENVIADO: o `metadata` leva `notice_id` e `message_id` (a mensagem 1) e o dedupe é por eles. O mesmo aviso remarcado
#   reaproveita a linha (`Scheduler::RESET`), mas sai com outra mensagem 1: falhar de novo gera outro alerta.
#
# Nunca altera a reunião (J5-A4).
class Crm::BookingV2::Notices::AgentAlert
  SOURCE = 'booking_agent_alert'.freeze
  ACTIVITIES = {
    'confirmed' => 'booking_client_confirmed', 'canceled' => 'booking_client_canceled',
    'rescheduled' => 'booking_client_rescheduled', 'rebooked' => 'booking_client_rebooked',
    'notice_failed' => 'booking_notice_failed',
    'notice_stop_failed' => 'booking_notice_failed',
    'notices_stopped' => 'booking_notices_stopped'
  }.freeze
  SILENT = %w[notices_stopped].freeze
  ONCE_PER_MEETING = %w[notice_failed].freeze
  ONCE_PER_NOTICE = %w[notice_stop_failed].freeze
  # Eventos que não são ação do cliente: a atividade registra `by: 'system'`.
  SYSTEM_EVENTS = %w[notice_failed notice_stop_failed].freeze

  def initialize(meeting, event, payload = {})
    @meeting = meeting
    @event = event.to_s
    @payload = payload
  end

  def perform
    raise ArgumentError, "unknown booking alert: #{event}" unless ACTIVITIES.key?(event)

    log_activity
    return if SILENT.include?(event)
    return if (ONCE_PER_MEETING + ONCE_PER_NOTICE).include?(event) && already_alerted?

    create_task!
  end

  private

  attr_reader :meeting, :event, :payload

  def card
    meeting.card
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: card, actor: nil, event_type: ACTIVITIES[event],
      payload: { meeting_id: meeting.id, starts_at: meeting.starts_at.iso8601, by: author }.merge(payload)
    ).perform
  end

  def author
    SYSTEM_EVENTS.include?(event) ? 'system' : 'client'
  end

  def already_alerted?
    scope = Crm::FollowUp.where(account_id: meeting.account_id, card_id: card.id)
                         .where("crm_follow_ups.metadata->>'source' = ?", SOURCE)
                         .where("crm_follow_ups.metadata->>'meeting_id' = ?", meeting.id.to_s)
                         .where("crm_follow_ups.metadata->>'event' = ?", event)
    ONCE_PER_NOTICE.include?(event) ? scope.exists?(sent_notice_condition) : scope.exists?
  end

  def sent_notice_condition
    ids = payload.to_h.with_indifferent_access
    ["crm_follow_ups.metadata->>'notice_id' = ? AND crm_follow_ups.metadata->>'message_id' = ?", ids[:notice_id].to_s, ids[:message_id].to_s]
  end

  def create_task!
    Crm::FollowUp.create!(
      account_id: meeting.account_id, card: card, contact: card.contact, assignee: meeting.created_by, created_by: nil,
      title: title.first(255), due_at: Time.current, timezone: meeting.timezone.presence || 'UTC',
      follow_up_type: :task, automation_mode: :reminder_only, status: :pending,
      metadata: alert_metadata
    )
  end

  def alert_metadata
    details = payload.to_h.with_indifferent_access.slice(:kind, :reason, :notice_id, :message_id).transform_values(&:to_s)
    { 'source' => SOURCE, 'meeting_id' => meeting.id, 'event' => event, 'contact_name' => client_name,
      'starts_at' => meeting.starts_at.iso8601 }.merge(details.to_h).compact_blank
  end

  def client_name
    card.contact&.name.presence || card.title
  end

  def title
    text = I18n.t("crm.booking_v2.agent_alerts.#{event}", name: client_name, when: Crm::BookingV2::Notices::Text.when_text(meeting),
                                                          locale: locale)
    [text, reason_text].compact.join(' ')
  end

  # Motivo em texto simples depois do aviso, quando a atendente pode agir sobre ele (#1270).
  def reason_text
    reason = payload.to_h.with_indifferent_access[:reason].to_s
    return if reason.blank?

    key = "crm.booking_v2.agent_alerts.reasons.#{reason}"
    I18n.t(key, locale: locale) if I18n.exists?(key, locale)
  end

  def locale
    Crm::BookingV2::Notices::Text.locale(meeting.account)
  end
end
