# O que pede atenção do admin nas páginas novas (#1187, J8-A9): página ou link individual cujo responsável não é
# mais elegível (`HostEligibility`) — saiu da conta, perdeu a função — e quantas reuniões futuras dessa página
# ficam com essa pessoa.
#
# A reunião aponta a página por `metadata['booking_profile_id']` (gravado por quem reserva pela página v2).
class Crm::BookingV2::AttentionReport
  PAGE_KEY = 'booking_profile_id'.freeze

  Entry = Struct.new(:profile, :link, :user_id, :reason, :upcoming_meetings_count, keyword_init: true)

  def self.upcoming_meetings(profile)
    profile.account.crm_meetings.upcoming.where("crm_meetings.metadata ->> 'booking_profile_id' = ?", profile.id.to_s)
  end

  def initialize(account:)
    @account = account
  end

  def entries
    @entries ||= pages.flat_map { |profile| entries_for(profile) }
  end

  def attention?(profile)
    entries.any? { |entry| entry.profile.id == profile.id }
  end

  private

  attr_reader :account

  def pages
    account.crm_agent_booking_profiles.new_pages.includes(:default_assignee, agent_booking_links: :agent).order(:id)
  end

  def entries_for(profile)
    return per_agent_entries(profile) if profile.assignment_mode_per_agent?
    return [] if eligible?(profile.default_assignee)

    reason = profile.default_assignee_id.blank? ? 'host_missing' : 'host_ineligible'
    [build_entry(profile, nil, profile.default_assignee_id, reason)]
  end

  def per_agent_entries(profile)
    links = profile.agent_booking_links.select(&:enabled?)
    return [build_entry(profile, nil, nil, 'host_missing')] if links.empty?

    links.reject { |link| eligible?(link.agent) }.map { |link| build_entry(profile, link, link.agent_id, 'host_ineligible') }
  end

  def build_entry(profile, link, user_id, reason)
    count = user_id.present? ? self.class.upcoming_meetings(profile).by_agent(user_id).count : 0
    Entry.new(profile: profile, link: link, user_id: user_id, reason: reason, upcoming_meetings_count: count)
  end

  def eligible?(user)
    Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
  end
end
