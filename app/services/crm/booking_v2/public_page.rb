# Página pública v2 (#1189) a partir do slug que o visitante traz em `/book/:slug`: só o slug opaco autoriza, nunca
# um id da URL.
#
# O slug é de uma página nova (page_version 2) com responsável fixo OU do link individual de uma página nova
# `per_agent`. O slug-base de uma página `per_agent` não tem responsável e não é público (igual ao v1), salvo na
# prévia, que usa o primeiro link utilizável. Página antiga, slug desconhecido ou flag da conta desligada: `find`
# devolve nil e o controller responde o 404 uniforme.
#
# Estados:
# - `paused?`: página (ou link individual) despublicada e sem prévia válida. A página mostra só o aviso de pausa.
# - `readable?`: pode mostrar dados e horários (publicada ou em prévia) e o responsável ainda pode atender.
# - `bookable?`: pode reservar. A prévia NUNCA reserva: exige página e link publicados.
class Crm::BookingV2::PublicPage
  attr_reader :slug, :profile, :link

  def self.find(slug, preview_token: nil)
    return if slug.blank?

    page = new(slug.to_s, preview_token.to_s)
    page if page.found?
  end

  def initialize(slug, preview_token)
    @slug = slug
    @slug_link = ::Crm::AgentBookingLink.includes(:agent, booking_profile: :account).find_by(slug: slug)
    @profile = @slug_link&.booking_profile || ::Crm::AgentBookingProfile.includes(:account, :default_assignee).find_by(slug: slug)
    @preview = preview_token.present? && preview_for?(preview_token)
    @link = @slug_link || preview_link
  end

  def found?
    return false if profile.blank? || !profile.new_page? || !::Crm::Config.booking_v2_enabled?(profile.account)
    return link.present? if profile.assignment_mode_per_agent?

    @slug_link.nil?
  end

  def account
    profile.account
  end

  def preview?
    @preview
  end

  def published?
    profile.enabled? && (link.nil? || link.enabled?)
  end

  def paused?
    !preview? && !published?
  end

  def readable?
    (published? || preview?) && host_eligible?
  end

  def bookable?
    published? && host_eligible?
  end

  def host
    link ? link.agent : profile.default_assignee
  end

  def host_eligible?
    return @host_eligible if defined?(@host_eligible)

    @host_eligible = ::Crm::BookingV2::HostEligibility.eligible?(account: account, user: host)
  end

  private

  def preview_for?(token)
    return false if profile.blank?

    payload = ::Crm::BookingV2::Tokens.verify('preview', token)
    payload.is_a?(Hash) && payload['p'].to_i == profile.id
  end

  # Prévia do slug-base de uma página `per_agent`: mostra a página como a vê o cliente do primeiro link utilizável.
  def preview_link
    return unless @preview && profile.assignment_mode_per_agent?

    profile.agent_booking_links.includes(:agent).order(:id).find do |candidate|
      candidate.enabled? && ::Crm::BookingV2::HostEligibility.eligible?(account: account, user: candidate.agent)
    end
  end
end
