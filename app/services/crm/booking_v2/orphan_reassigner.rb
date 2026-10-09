# Quando uma pessoa sai da conta (#1187, J8-A9): as reuniões futuras agendadas com ela passam para o responsável
# padrão da página (se ainda elegível) ou para o primeiro administrador, e os links individuais dela são
# desligados. Sem isso a reunião ficaria com um `created_by` de fora da conta, que nem cancelar se consegue
# (`Crm::Meeting#validate_created_by_account`). Cada card afetado ganha uma atividade para o admin ver.
#
# Ligado ao `after_destroy_commit` de `AccountUser` em `config/initializers/crm_booking_account_user.rb`.
class Crm::BookingV2::OrphanReassigner
  EVENT_TYPE = 'meeting_host_reassigned'.freeze

  def initialize(account_id:, user_id:)
    @account = Account.find_by(id: account_id)
    @user_id = user_id
  end

  def perform
    return if account.blank? || user_id.blank?
    return if account.account_users.exists?(user_id: user_id)

    disable_links
    orphan_meetings.find_each { |meeting| reassign(meeting) }
  end

  private

  attr_reader :account, :user_id

  # Sem validação de propósito: a do link exige que o agente seja da conta, e ele acabou de sair. Desligar é o
  # único efeito; o mesmo padrão do Agents::DestroyJob ao desatribuir conversas.
  def disable_links
    # rubocop:disable Rails/SkipsModelValidations
    account.crm_agent_booking_links.where(agent_id: user_id, enabled: true).update_all(enabled: false, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def orphan_meetings
    account.crm_meetings.upcoming.by_agent(user_id).includes(:card)
  end

  def reassign(meeting)
    profile = page_of(meeting)
    new_host = page_host(profile) || first_administrator
    if new_host.blank?
      Rails.logger.warn("[booking_v2] meeting #{meeting.id} has no host to take over after user #{user_id} left account #{account.id}")
      return
    end

    meeting.update!(created_by: new_host)
    log(meeting, new_host, profile)
  rescue ActiveRecord::RecordInvalid => e
    # Uma reunião com dado antigo inválido não trava as outras; fica no log para o admin tratar.
    Rails.logger.warn("[booking_v2] meeting #{meeting.id} not reassigned: #{e.record.errors.full_messages.to_sentence}")
  end

  def page_of(meeting)
    profile_id = meeting.metadata.to_h[Crm::BookingV2::AttentionReport::PAGE_KEY]
    return if profile_id.blank?

    account.crm_agent_booking_profiles.find_by(id: profile_id)
  end

  def page_host(profile)
    host = profile&.default_assignee
    return if host.blank? || host.id == user_id

    host if Crm::BookingV2::HostEligibility.eligible?(account: account, user: host)
  end

  def first_administrator
    @first_administrator ||= account.account_users.human.administrator.where.not(user_id: user_id).order(:id).first&.user
  end

  def log(meeting, new_host, profile)
    Crm::ActivityLogger.new(
      card: meeting.card, actor: nil, event_type: EVENT_TYPE,
      payload: { meeting_id: meeting.id, from_user_id: user_id, to_user_id: new_host.id, booking_profile_id: profile&.id }
    ).perform
  end
end
