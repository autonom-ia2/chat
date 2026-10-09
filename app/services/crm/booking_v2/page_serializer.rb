# JSON das páginas de agendamento novas (page_version 2) para a tela de Configurações › Agendamento (#1187).
# Pessoas aparecem só por id, nome e foto: e-mail nunca sai daqui. Não lista membros de caixa (J8-A5).
class Crm::BookingV2::PageSerializer
  include Rails.application.routes.url_helpers

  def self.person(user)
    return if user.blank?

    { id: user.id, name: user.name, avatar_url: user.avatar_url }
  end

  # `upcoming_meetings_count`: a lista passa a contagem já feita em lote (AttentionReport.upcoming_counts); sem ela,
  # conta só esta página. `paused_user_ids`: quem pausou a própria agenda (#1195), também em lote na lista.
  # `orphaned`: `AttentionReport#orphaned` desta página.
  def initialize(profile, attention: false, upcoming_meetings_count: nil, paused_user_ids: nil, orphaned: [])
    @profile = profile
    @attention = attention
    @upcoming_meetings_count = upcoming_meetings_count
    @paused_user_ids = paused_user_ids
    @orphaned = orphaned
  end

  def summary
    {
      id: profile.id, slug: profile.slug, title: profile.title, enabled: profile.enabled, public_url: public_url,
      locations: profile.locations, assignment_mode: profile.assignment_mode,
      upcoming_meetings_count: upcoming_meetings_count,
      attention: attention, orphaned: @orphaned, paused_people: paused_people
    }
  end

  def full
    summary.merge(settings, branding, assignment).merge(created_at: profile.created_at&.iso8601, updated_at: profile.updated_at&.iso8601)
  end

  private

  attr_reader :profile, :attention

  def upcoming_meetings_count
    @upcoming_meetings_count || Crm::BookingV2::AttentionReport.upcoming_meetings(profile).count
  end

  # Quem atende esta página e pausou a própria agenda em Meus horários (#1195): o admin vê no cartão.
  def paused_people
    hosts = host_users
    paused = @paused_user_ids || paused_ids(hosts)
    hosts.select { |user| paused.include?(user.id) }.map { |user| { id: user.id, name: user.name } }
  end

  def paused_ids(hosts)
    Crm::AgentAvailability.where(account_id: profile.account_id, paused: true, user_id: hosts.map(&:id)).pluck(:user_id)
  end

  def host_users
    return [profile.default_assignee].compact if profile.assignment_mode_fixed?

    profile.agent_booking_links.select(&:enabled?).filter_map(&:agent)
  end

  def settings
    {
      description: profile.description, duration_minutes: profile.duration_minutes, slot_durations: profile.slot_durations,
      buffer_minutes: profile.buffer_minutes, booking_window_days: profile.booking_window_days,
      min_notice_minutes: profile.min_notice_minutes, working_hours: profile.working_hours, timezone: profile.resolved_timezone,
      calendar_inbox_id: profile.inbox_id, invite_text: profile.invite_text, invite_ttl_days: profile.invite_ttl_days,
      close_holidays: profile.close_holidays
    }
  end

  def branding
    {
      template_key: profile.template_key, brand: profile.brand, contact_phone: profile.contact_phone,
      logo_url: attachment_url(profile.logo), photo_url: attachment_url(profile.photo)
    }
  end

  def assignment
    {
      default_pipeline_id: profile.default_pipeline_id, default_stage_id: profile.default_stage_id,
      host: self.class.person(profile.default_assignee), people: people
    }
  end

  def people
    return [self.class.person(profile.default_assignee)].compact if profile.assignment_mode_fixed?

    profile.agent_booking_links.select(&:enabled?).map do |link|
      self.class.person(link.agent).merge(link_slug: link.slug, public_url: "#{base_url}/book/#{link.slug}")
    end
  end

  def attachment_url(attachment)
    return unless attachment.attached?

    url_for(attachment)
  end

  def public_url
    "#{base_url}/book/#{profile.slug}"
  end

  def base_url
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end
end
