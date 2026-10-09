# Páginas que podem receber convite (#1190): páginas novas (page_version 2) publicadas e com alguém que pode
# atender. Responsável inelegível (saiu da conta, perdeu a função) deixa a página como pausada, igual ao servir a
# página pública (`HostEligibility`).
class Crm::BookingV2::InvitePages
  def initialize(account)
    @account = account
  end

  def usable
    @usable ||= account.crm_agent_booking_profiles.new_pages.enabled
                       .includes(:default_assignee, agent_booking_links: :agent).order(:id).select { |page| usable?(page) }
  end

  def usable?(page)
    return false unless page.new_page? && page.enabled? && page.account_id == account.id
    return eligible?(page.default_assignee) if page.assignment_mode_fixed?

    page.agent_booking_links.any? { |link| link_usable?(link) }
  end

  def link_usable?(link)
    link.enabled? && eligible?(link.agent)
  end

  # A página em que a pessoa atende (responsável fixo ou link individual ativo); senão a primeira publicada.
  def default_for(user)
    usable.find { |page| attends?(page, user) } || usable.first
  end

  # Link individual da pessoa numa página `per_agent`; nil quando a pessoa não atende nela.
  def link_for(page, user)
    return unless page.assignment_mode_per_agent?

    page.agent_booking_links.find { |link| link.agent_id == user&.id && link_usable?(link) }
  end

  private

  attr_reader :account

  def attends?(page, user)
    return page.default_assignee_id == user&.id if page.assignment_mode_fixed?

    link_for(page, user).present?
  end

  def eligible?(user)
    Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
  end
end
