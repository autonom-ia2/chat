# Passa UMA reunião de uma pessoa para outra (#1195): é o que muda quando o responsável muda. Usado por quem sai da
# conta (`OrphanReassigner`, J8-A9) e pelo "Passar reuniões" do admin (`Reassigner`, J8-A10).
#
# Muda o responsável da reunião (`created_by`, que é quem a agenda ocupa) e o lembrete do agente ainda pendente que
# estava com a pessoa antiga, e registra `meeting_host_reassigned` no card. O dono do card e os convidados ficam
# como estão: o cliente continua o mesmo, e o card pode ter outras conversas e reuniões com outras pessoas.
# Quem chama segura a trava de agente (`Booker::LOCK_NS_AGENT`) e a transação.
class Crm::BookingV2::MeetingHandover
  EVENT_TYPE = 'meeting_host_reassigned'.freeze

  def initialize(meeting:, from_user_id:, to_user:, actor: nil, reason: nil)
    @meeting = meeting
    @from_user_id = from_user_id
    @to_user = to_user
    @actor = actor
    @reason = reason
  end

  def perform
    meeting.update!(created_by: to_user)
    move_reminder
    log_activity
    meeting
  end

  private

  attr_reader :meeting, :from_user_id, :to_user

  def move_reminder
    reminder = meeting.reminder
    return if reminder.blank? || !reminder.pending? || reminder.assignee_id != from_user_id

    # Só a pessoa do lembrete muda, e ela já foi conferida (é quem recebe a reunião). Sem validação de propósito:
    # quando quem marcou saiu da conta (OrphanReassigner), o `created_by` do lembrete deixa o registro inválido e o
    # update! recusaria trocar só o assignee.
    reminder.update_columns(assignee_id: to_user.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def log_activity
    payload = { meeting_id: meeting.id, from_user_id: from_user_id, to_user_id: to_user.id,
                booking_profile_id: meeting.metadata.to_h['booking_profile_id'], reason: @reason }.compact
    Crm::ActivityLogger.new(card: meeting.card, actor: @actor, event_type: EVENT_TYPE, payload: payload).perform
  end
end
