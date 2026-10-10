# O que pede atenção do admin nas páginas novas (#1187, J8-A9): página ou link individual cujo responsável não é
# mais elegível (`HostEligibility`) — saiu da conta, perdeu a função — e quantas reuniões futuras dessa página
# ficam com essa pessoa.
#
# A reunião aponta a página por `metadata['booking_profile_id']` (gravado por quem reserva pela página v2).
# `attention?` olha só a página pedida (a lista e a tela de uma página não varrem as outras); `entries` é o
# relatório da conta inteira.
#
# Reuniões que ficaram com quem não atende mais (#1195): reunião futura de página nova cujo responsável (`created_by`)
# não é mais elegível — saiu da conta e quem recebia estava ocupado (`OrphanReassigner`), ou perdeu a função. Fica à
# parte de `attention?` (que diz "quem atende a página não pode receber"): `orphaned` dá a pessoa e quantas reuniões,
# o cartão da página mostra o aviso até o admin passar essas reuniões em "Passar reuniões", e `entries` traz as duas.
class Crm::BookingV2::AttentionReport
  PAGE_KEY = 'booking_profile_id'.freeze

  Entry = Struct.new(:profile, :link, :user_id, :reason, :upcoming_meetings_count, keyword_init: true)

  def self.upcoming_meetings(profile)
    profile.account.crm_meetings.upcoming.where("crm_meetings.metadata ->> 'booking_profile_id' = ?", profile.id.to_s)
  end

  # Reuniões futuras por página, numa consulta só: { profile_id => quantidade }.
  def self.upcoming_counts(profiles)
    return {} if profiles.empty?

    account_id = profiles.first.account_id
    Crm::Meeting.upcoming.where(account_id: account_id)
                .where("crm_meetings.metadata ->> 'booking_profile_id' IN (?)", profiles.map { |profile| profile.id.to_s })
                .group(Arel.sql("crm_meetings.metadata ->> 'booking_profile_id'")).count
                .transform_keys(&:to_i)
  end

  def initialize(account:)
    @account = account
  end

  def entries
    @entries ||= pages.flat_map { |profile| entries_for(profile) + orphan_entries(profile) }
  end

  def attention?(profile)
    return false unless profile.new_page? && profile.account_id == account.id

    flagged_hosts(profile).any?
  end

  # [{ id:, name:, upcoming_meetings_count: }] de quem não atende mais e ainda tem reunião futura desta página. Uma
  # consulta para as páginas novas da conta inteira, feita uma vez por relatório. Nome sim, e-mail nunca.
  def orphaned(profile)
    orphan_rows.fetch(profile.id, [])
  end

  private

  attr_reader :account

  def pages
    account.crm_agent_booking_profiles.new_pages.includes(:default_assignee, agent_booking_links: :agent).order(:id)
  end

  # [link, user_id, motivo] de cada responsável que impede a página de atender; vazio = página em ordem.
  def flagged_hosts(profile)
    return per_agent_flags(profile) if profile.assignment_mode_per_agent?
    return [] if eligible?(profile.default_assignee)

    [[nil, profile.default_assignee_id, profile.default_assignee_id.blank? ? 'host_missing' : 'host_ineligible']]
  end

  def per_agent_flags(profile)
    links = profile.agent_booking_links.select(&:enabled?)
    return [[nil, nil, 'host_missing']] if links.empty?

    links.reject { |link| eligible?(link.agent) }.map { |link| [link, link.agent_id, 'host_ineligible'] }
  end

  def entries_for(profile)
    flagged_hosts(profile).map { |link, user_id, reason| build_entry(profile, link, user_id, reason) }
  end

  def build_entry(profile, link, user_id, reason)
    count = user_id.present? ? self.class.upcoming_meetings(profile).by_agent(user_id).count : 0
    Entry.new(profile: profile, link: link, user_id: user_id, reason: reason, upcoming_meetings_count: count)
  end

  def orphan_entries(profile)
    orphaned(profile).map do |person|
      Entry.new(profile: profile, link: nil, user_id: person[:id], reason: 'meetings_orphaned',
                upcoming_meetings_count: person[:upcoming_meetings_count])
    end
  end

  def orphan_rows
    @orphan_rows ||= begin
      counts = upcoming_by_page_and_host
      users = User.where(id: counts.keys.map(&:last).uniq).index_by(&:id)
      counts.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((page_id, user_id), count), rows|
        next if eligible?(users[user_id])

        rows[page_id] << { id: user_id, name: users[user_id]&.name, upcoming_meetings_count: count }
      end
    end
  end

  # { [page_id, created_by_id] => quantidade } das reuniões futuras das páginas novas da conta.
  def upcoming_by_page_and_host
    page_ids = account.crm_agent_booking_profiles.new_pages.pluck(:id).map(&:to_s)
    return {} if page_ids.empty?

    account.crm_meetings.upcoming.where("crm_meetings.metadata ->> 'booking_profile_id' IN (?)", page_ids)
           .group(Arel.sql("crm_meetings.metadata ->> 'booking_profile_id'"), :created_by_id).count
           .transform_keys { |page_id, user_id| [page_id.to_i, user_id] }
  end

  def eligible?(user)
    return false if user.blank?

    @eligible ||= {}
    @eligible.fetch(user.id) { @eligible[user.id] = Crm::BookingV2::HostEligibility.eligible?(account: account, user: user) }
  end
end
