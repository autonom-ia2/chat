# Quem atende numa página nova (#1187, J8-A13): pessoas da conta, não membros de caixa. Uma pessoa = modo `fixed`
# (responsável padrão); duas ou mais = `per_agent`, com um `Crm::AgentBookingLink` por pessoa, sem caixa.
# Quem sai da lista tem o link desligado (não apagado: o slug já pode ter sido compartilhado).
class Crm::BookingV2::PagePeople
  class InvalidPeople < StandardError; end

  def self.eligible(account)
    account.account_users.human.includes(:user).order(:id).filter_map do |account_user|
      user = account_user.user
      user if Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
    end
  end

  def initialize(profile)
    @profile = profile
  end

  def assign!(user_ids)
    people = resolve(user_ids)
    ActiveRecord::Base.transaction do
      people.one? ? assign_fixed(people.first) : assign_per_agent(people)
    end
  end

  private

  attr_reader :profile

  def resolve(user_ids)
    ids = Array(user_ids).map(&:to_i).uniq
    by_id = self.class.eligible(profile.account).index_by(&:id)
    raise InvalidPeople if ids.empty? || ids.any? { |id| by_id[id].blank? }

    ids.map { |id| by_id[id] }
  end

  def assign_fixed(user)
    profile.update!(assignment_mode: :fixed, default_assignee: user)
    disable_links_except([])
  end

  def assign_per_agent(people)
    profile.update!(assignment_mode: :per_agent, default_assignee: people.first)
    people.each { |user| enable_link(user) }
    disable_links_except(people.map(&:id))
  end

  def enable_link(user)
    link = profile.agent_booking_links.find_or_initialize_by(agent_id: user.id)
    link.account = profile.account
    link.enabled = true
    link.save!
  end

  def disable_links_except(user_ids)
    profile.agent_booking_links.enabled.where.not(agent_id: user_ids).find_each { |link| link.update!(enabled: false) }
  end
end
