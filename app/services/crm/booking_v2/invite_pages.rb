# Páginas que podem receber convite (#1190): páginas novas (page_version 2) publicadas e com alguém que pode
# atender. Responsável inelegível (saiu da conta, perdeu a função) deixa a página como pausada, igual ao servir a
# página pública (`HostEligibility`).
#
# `status` é a REGRA ÚNICA do "esta página marca?" (#1305): o convite, o painel, a agenda da IA
# (`Native::Agenda.estado`) e o estado que a tela de páginas mostra (`PageSerializer#ai_status`) leem daqui, para
# nunca divergirem. `receiver` é quem recebe a reunião quando ninguém está atribuído à conversa.
#
# Agenda pausada em "Meus horários" (#1195): a página continua no ar e recebendo convite (`usable?` não muda), mas
# quem pausou não tem horário (`Slots#host_paused?`). Responsável fixo pausado, ou todos os links de quem pausou,
# é `agenda_pausada`; no link por pessoa, o primeiro link de quem NÃO pausou recebe (`link_for`).
class Crm::BookingV2::InvitePages
  ACTIVE = 'ativa'.freeze
  PAUSED = 'pausada'.freeze
  NO_HOST = 'sem_responsavel'.freeze
  AGENDA_PAUSED = 'agenda_pausada'.freeze
  # Estados em que a página continua recebendo convite e reserva pelo painel (a regra de antes do #1305).
  SERVES = [ACTIVE, AGENDA_PAUSED].freeze

  def initialize(account)
    @account = account
  end

  def usable
    @usable ||= account.crm_agent_booking_profiles.new_pages.enabled
                       .includes(:default_assignee, agent_booking_links: :agent).order(:id).select { |page| usable?(page) }
  end

  def usable?(page)
    page.new_page? && page.account_id == account.id && SERVES.include?(status(page))
  end

  # 'ativa' | 'pausada' (despublicada) | 'sem_responsavel' (ninguém que possa atender) | 'agenda_pausada' (quem
  # atende pausou a própria agenda).
  def status(page)
    return PAUSED unless page.enabled?
    return NO_HOST unless attended?(page)

    attended_unpaused?(page) ? ACTIVE : AGENDA_PAUSED
  end

  # Quem recebe a reunião sem ninguém atribuído: o responsável fixo, ou o primeiro link ativo (`link_for`). nil sem
  # ninguém que possa atender.
  def receiver(page)
    return (page.default_assignee if eligible?(page.default_assignee)) if page.assignment_mode_fixed?

    link_for(page, nil)&.agent
  end

  def link_usable?(link)
    link.enabled? && eligible?(link.agent)
  end

  # O convite ainda leva a uma página que atende: a página utilizável e, se houver, o link individual também.
  def invite_usable?(invite)
    usable?(invite.booking_profile) && (invite.booking_link.blank? || link_usable?(invite.booking_link))
  end

  # A página em que a pessoa atende (responsável fixo ou link individual ativo); senão a primeira publicada.
  def default_for(user)
    usable.find { |page| attends?(page, user) } || usable.first
  end

  # Link que o convite leva numa página `per_agent`: o da própria pessoa; se ela não atende ali, o primeiro link
  # ativo da página de quem não pausou a agenda (o endereço-base de `per_agent` não abre sozinho). nil em página de
  # responsável fixo. É também quem recebe a reunião da IA sem ninguém atribuído e o `recebe` da tela de páginas.
  def link_for(page, user)
    return unless page.assignment_mode_per_agent?

    own_link(page, user) || first_link(page)
  end

  private

  attr_reader :account

  def attended?(page)
    return eligible?(page.default_assignee) if page.assignment_mode_fixed?

    page.agent_booking_links.any? { |link| link_usable?(link) }
  end

  def attended_unpaused?(page)
    return !paused?(page.default_assignee) if page.assignment_mode_fixed?

    page.agent_booking_links.any? { |link| link_usable?(link) && !paused?(link.agent) }
  end

  # O primeiro link ativo (na ordem da associação) de quem não pausou a agenda; todos pausados, o primeiro ativo.
  def first_link(page)
    usable_links = page.agent_booking_links.select { |link| link_usable?(link) }
    usable_links.find { |link| !paused?(link.agent) } || usable_links.first
  end

  def own_link(page, user)
    page.agent_booking_links.find { |link| link.agent_id == user&.id && link_usable?(link) }
  end

  def attends?(page, user)
    return page.default_assignee_id == user&.id if page.assignment_mode_fixed?

    own_link(page, user).present?
  end

  # Uma consulta por instância, não uma por pessoa (`HostEligibility.eligible_user_ids`).
  def eligible?(user)
    user.present? && eligible_ids.include?(user.id)
  end

  def eligible_ids
    @eligible_ids ||= Crm::BookingV2::HostEligibility.eligible_user_ids(account: account)
  end

  # Quem pausou a própria agenda em Meus horários: uma consulta por instância.
  def paused?(user)
    user.present? && paused_ids.include?(user.id)
  end

  def paused_ids
    @paused_ids ||= Crm::AgentAvailability.where(account_id: account.id, paused: true).pluck(:user_id).to_set
  end
end
