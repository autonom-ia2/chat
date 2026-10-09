# Quando uma pessoa sai da conta (#1187, J8-A9): as reuniões futuras agendadas com ela passam para o responsável
# padrão da página (se ainda elegível) ou para o primeiro administrador, e os links individuais dela são
# desligados. Sem isso a reunião ficaria com um `created_by` de fora da conta, que nem cancelar se consegue
# (`Crm::Meeting#validate_created_by_account`). Cada card afetado ganha uma atividade para o admin ver.
#
# Só age com a flag `crm_booking_v2` ligada na conta, e só no que é do agendamento novo: reuniões `scheduled`
# futuras internas (`provider: :internal`) ou criadas por uma página nova (`metadata['booking_profile_id']`), e
# links de páginas `page_version: 2`. Reunião Google/Microsoft antiga e link de página antiga ficam como estão.
#
# Sem dupla reserva (#1195): antes de passar, confere se quem recebe está livre naquele horário, com a mesma regra e
# as mesmas travas do "Passar reuniões" (`HostSchedule`): as de agente de quem sai e de todos que podem receber, numa
# vez só e em ordem crescente. Ocupada, a reunião NÃO passa: fica com quem saiu e a página aparece com aviso de
# atenção (`AttentionReport#orphaned`), com o nome da pessoa e quantas reuniões ficaram; o admin escolhe para quem
# passar em "Passar reuniões". O mesmo vale para reunião sem ninguém para receber e para reunião com dado inválido.
#
# Ligado ao `after_destroy_commit` de `AccountUser` em `config/initializers/crm_booking_account_user.rb`.
class Crm::BookingV2::OrphanReassigner
  EVENT_TYPE = Crm::BookingV2::MeetingHandover::EVENT_TYPE

  def initialize(account_id:, user_id:)
    @account = Account.find_by(id: account_id)
    @user_id = user_id.presence&.to_i
  end

  def perform
    return if account.blank? || user_id.blank?
    return unless Crm::Config.booking_v2_enabled?(account)
    return if account.account_users.exists?(user_id: user_id)

    # Mesma trava de agente da reserva (Booker): uma reserva em andamento termina antes de olharmos as reuniões, e
    # a próxima já vê a pessoa fora da conta. Quem pode receber é calculado antes, para travar todos na mesma ordem.
    ActiveRecord::Base.transaction do
      Crm::BookingV2::HostSchedule.lock!(locked_ids)
      disable_links
      Crm::AgentAvailability.where(account_id: account.id, user_id: user_id).delete_all
      schedule = Crm::BookingV2::HostSchedule.new(account: account)
      orphan_meetings.each { |meeting| reassign(meeting, schedule) }
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
    account.crm_meetings.upcoming.by_agent(user_id).where("crm_meetings.metadata ->> 'booking_profile_id' IS NOT NULL")
           .includes(:card, :reminder).order(:starts_at, :id)
  end

  # Quem sai, o responsável de cada página das reuniões dela e o primeiro administrador.
  def locked_ids
    @locked_ids ||= begin
      page_ids = orphan_meetings.filter_map { |meeting| meeting.metadata.to_h[Crm::BookingV2::AttentionReport::PAGE_KEY] }.uniq
      hosts = account.crm_agent_booking_profiles.where(id: page_ids).pluck(:default_assignee_id)
      [user_id, *hosts, first_administrator&.id].compact.uniq
    end
  end

  def reassign(meeting, schedule)
    profile = page_of(meeting)
    new_host = page_host(profile)
    fallback = new_host.blank?
    new_host ||= first_administrator
    return keep(meeting, 'no_host') if new_host.blank?
    # A página trocou de responsável depois das travas: sem a trava dele não dá para conferir a agenda.
    return keep(meeting, 'host_changed', new_host) unless locked_ids.include?(new_host.id)
    return keep(meeting, 'host_busy', new_host) unless schedule.free?(meeting, new_host.id)

    hand_over(meeting, new_host, schedule)
    log_reassignment(meeting, new_host, profile, fallback)
  rescue ActiveRecord::RecordInvalid => e
    # Uma reunião com dado antigo inválido não trava as outras; fica com quem saiu e aparece na atenção do admin.
    keep(meeting, "invalid: #{e.record.errors.full_messages.to_sentence}")
  end

  # Ponto de salvamento por reunião: se a atividade do card falhar, a troca de responsável dela volta junto.
  def hand_over(meeting, new_host, schedule)
    ActiveRecord::Base.transaction(requires_new: true) do
      Crm::BookingV2::MeetingHandover.new(meeting: meeting, from_user_id: user_id, to_user: new_host).perform
    end
    schedule.reserve(meeting, new_host.id)
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

  # A reunião fica com quem saiu: o `AttentionReport` mostra a página com aviso até o admin passar a reunião.
  def keep(meeting, reason, candidate = nil)
    Rails.logger.warn(
      "[booking_v2] meeting #{meeting.id} kept with user #{user_id} after leaving account #{account.id} " \
      "(#{reason}, candidate #{candidate&.id.inspect})"
    )
  end

  def log_reassignment(meeting, new_host, profile, fallback)
    target = fallback ? 'first_administrator' : 'page_default_host'
    Rails.logger.info(
      "[booking_v2] meeting #{meeting.id} reassigned from user #{user_id} to user #{new_host.id} (#{target}) " \
      "account #{account.id} booking_profile #{profile&.id.inspect}"
    )
  end
end
