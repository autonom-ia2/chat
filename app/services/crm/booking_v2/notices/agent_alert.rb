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
#
# Nunca altera a reunião (J5-A4).
class Crm::BookingV2::Notices::AgentAlert
  SOURCE = 'booking_agent_alert'.freeze
  ACTIVITIES = {
    'confirmed' => 'booking_client_confirmed', 'canceled' => 'booking_client_canceled',
    'rescheduled' => 'booking_client_rescheduled', 'rebooked' => 'booking_client_rebooked',
    'notice_failed' => 'booking_notice_failed',
    'notices_stopped' => 'booking_notices_stopped'
  }.freeze
  SILENT = %w[notices_stopped].freeze
  ONCE_PER_MEETING = %w[notice_failed].freeze
  # Eventos que não são ação do cliente: a atividade registra `by: 'system'`.
  SYSTEM_EVENTS = %w[notice_failed].freeze

  def initialize(meeting, event, payload = {})
    @meeting = meeting
    @event = event.to_s
    @payload = payload
  end

  def perform
    raise ArgumentError, "unknown booking alert: #{event}" unless ACTIVITIES.key?(event)

    log_activity
    return if SILENT.include?(event)
    return if ONCE_PER_MEETING.include?(event) && already_alerted?

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
    Crm::FollowUp.where(account_id: meeting.account_id, card_id: card.id)
                 .where("crm_follow_ups.metadata->>'source' = ?", SOURCE)
                 .where("crm_follow_ups.metadata->>'meeting_id' = ?", meeting.id.to_s)
                 .exists?(["crm_follow_ups.metadata->>'event' = ?", event])
  end

  def create_task!
    Crm::FollowUp.create!(
      account_id: meeting.account_id, card: card, contact: card.contact, assignee: meeting.created_by, created_by: nil,
      title: title.first(255), due_at: Time.current, timezone: meeting.timezone.presence || 'UTC',
      follow_up_type: :task, automation_mode: :reminder_only, status: :pending,
      metadata: { 'source' => SOURCE, 'meeting_id' => meeting.id, 'event' => event }
    )
  end

  def title
    name = card.contact&.name.presence || card.title
    I18n.t("crm.booking_v2.agent_alerts.#{event}", name: name, when: Crm::BookingV2::Notices::Text.when_text(meeting),
                                                   locale: Crm::BookingV2::Notices::Text.locale(meeting.account))
  end
end
