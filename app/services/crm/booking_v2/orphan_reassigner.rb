# Quando uma pessoa sai da conta (#1187, J8-A9): as reuniões futuras agendadas com ela passam para o responsável
# padrão da página (se ainda elegível) ou para o primeiro administrador, e os links individuais dela são
# desligados. Sem isso a reunião ficaria com um `created_by` de fora da conta, que nem cancelar se consegue
# (`Crm::Meeting#validate_created_by_account`). Cada card afetado ganha uma atividade para o admin ver.
#
# Só age com a flag `crm_booking_v2` ligada na conta, e só no que é do agendamento novo: reuniões `scheduled`
# futuras internas (`provider: :internal`) ou criadas por uma página nova (`metadata['booking_profile_id']`), e
# links de páginas `page_version: 2`. Reunião Google/Microsoft antiga e link de página antiga ficam como estão.
#
# Ligado ao `after_destroy_commit` de `AccountUser` em `config/initializers/crm_booking_account_user.rb`.
class Crm::BookingV2::OrphanReassigner
  EVENT_TYPE = Crm::BookingV2::MeetingHandover::EVENT_TYPE

  def initialize(account_id:, user_id:)
    @account = Account.find_by(id: account_id)
    @user_id = user_id
  end

  def perform
    return if account.blank? || user_id.blank?
    return unless Crm::Config.booking_v2_enabled?(account)
    return if account.account_users.exists?(user_id: user_id)

    # Mesma trava de agente da reserva (Booker): uma reserva em andamento termina antes de olharmos as reuniões, e
    # a próxima já vê a pessoa fora da conta.
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{Crm::BookingV2::Booker::LOCK_NS_AGENT}, #{user_id.to_i})")
      disable_links
      Crm::AgentAvailability.where(account_id: account.id, user_id: user_id).delete_all
      orphan_meetings.find_each { |meeting| reassign(meeting) }
    end
  end

  private

  attr_reader :account, :user_id

  # Sem validação de propósito: a do link exige que o agente seja da conta, e ele acabou de sair. Desligar é o
  # único efeito; o mesmo padrão do Agents::DestroyJob ao desatribuir conversas.
  def disable_links
    links = account.crm_agent_booking_links.where(agent_id: user_id, enabled: true)
                   .where(booking_profile_id: account.crm_agent_booking_profiles.new_pages.select(:id))
    # rubocop:disable Rails/SkipsModelValidations
    links.update_all(enabled: false, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def orphan_meetings
    # Só reuniões das páginas novas: as demais seguem o comportamento de sempre do sistema.
    account.crm_meetings.upcoming.by_agent(user_id).where("crm_meetings.metadata ->> 'booking_profile_id' IS NOT NULL").includes(:card)
  end

  def reassign(meeting)
    profile = page_of(meeting)
    new_host = page_host(profile)
    fallback = new_host.blank?
    new_host ||= first_administrator
    return log_no_host(meeting) if new_host.blank?

    Crm::BookingV2::MeetingHandover.new(meeting: meeting, from_user_id: user_id, to_user: new_host).perform
    log_reassignment(meeting, new_host, profile, fallback)
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

  def log_no_host(meeting)
    Rails.logger.warn("[booking_v2] meeting #{meeting.id} has no host to take over after user #{user_id} left account #{account.id}")
  end

  def log_reassignment(meeting, new_host, profile, fallback)
    target = fallback ? 'first_administrator' : 'page_default_host'
    Rails.logger.info(
      "[booking_v2] meeting #{meeting.id} reassigned from user #{user_id} to user #{new_host.id} (#{target}) " \
      "account #{account.id} booking_profile #{profile&.id.inspect}"
    )
  end
end
