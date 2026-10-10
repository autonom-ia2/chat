# Public, unauthenticated JSON API backing the /book/:slug page (P3 slice S6).
# Inherits PublicController (ActionController::Base + skip CSRF) — the EXACT pattern
# Chatwoot uses for its other public endpoints (CSAT, widget, portals). The opaque
# `slug` (SecureRandom.uuid) is the ONLY authorization; no account_id is ever read
# from the URL and Pundit is never invoked.
#
# Security posture:
#   - unknown / disabled slug => 404 (no enumeration, no PII).
#   - public payloads expose ONLY the agent display name, title/description,
#     duration, timezone and free slots — never contacts, inbox email, tokens or ids.
#   - #create validates + sanitizes input, enforces a honeypot + time-trap, and
#     delegates the double-book re-check + booking to PublicBookingService.
#   - any unexpected error => one generic message (no stack trace, no PII).
class Public::Api::V1::BookingController < PublicController
  before_action :ensure_booking_enabled
  before_action :set_profile, except: [:confirm]
  before_action :set_profile_for_confirm, only: [:confirm]

  rescue_from StandardError, with: :render_generic_error

  # GET /public/api/v1/booking/:slug
  def show
    render json: public_profile_payload
  end

  # GET /public/api/v1/booking/:slug/slots?date=YYYY-MM-DD
  def slots
    date = sanitized_date
    return render(json: { slots: [] }) if date.blank?

    available = Crm::Calendar::PublicAvailableSlots.new(
      profile: @profile, date: date, inbox: @link&.inbox, agent: booking_agent
    ).perform
    render json: { date: date, slots: available }
  end

  # POST /public/api/v1/booking/:slug
  #
  # STEP 1: validate + re-check the slot (fail-closed) and EMAIL a signed
  # verification link. NOTHING is created yet — the meeting is only created once
  # the booker proves email control by opening the link (#confirm). Returns 202.
  def create
    return render_bot_rejected if honeypot_tripped? || time_trap_tripped?

    initiated = Crm::Calendar::PublicBookingService.new(
      profile: @profile,
      name: booking_params[:name],
      email: booking_params[:email],
      starts_at: booking_params[:starts_at],
      link: @link
    ).initiate

    send_verification_email(initiated)

    render json: { status: 'verification_sent' }, status: :accepted
  rescue ArgumentError
    # Every rejectable condition (invalid input, slot taken, misconfigured profile)
    # collapses to a single generic 422 so nothing internal is leaked.
    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  end

  # POST /public/api/v1/booking/:slug/confirm
  #
  # STEP 2: the booker opened the email link. Verify the signed token (and that it
  # belongs to THIS slug — defense in depth) and create the contact/card/meeting
  # under an advisory lock. Returns the join URL on success.
  def confirm
    result = Crm::Calendar::PublicBookingService.confirm(token: params[:token])

    render json: { confirmed: true, join_url: result.join_url, starts_at: result.starts_at }
  rescue ArgumentError
    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  end

  private

  def ensure_booking_enabled
    head :not_found unless Crm::Config.calendar_meetings_enabled?
  end

  # A public slug is EITHER a fixed-mode profile's slug OR a per_agent link's slug.
  #   - link slug  -> @link + its (enabled, per_agent) profile.
  #   - fixed profile slug -> @profile, @link nil.
  #   - a per_agent profile's BASE slug is NOT directly bookable (no agent) => 404.
  def set_profile
    resolve_booking_context
    head :not_found if @profile.blank?
  end

  def resolve_booking_context
    @link = Crm::AgentBookingLink.enabled.find_by(slug: params[:slug])
    if @link.present?
      @profile = per_agent_legacy_profile(@link.booking_profile)
      @link = nil if @profile.blank?
      return
    end

    # Página nova (page_version 2) só é servida pela API v2, com as proteções dela (#1188).
    profile = Crm::AgentBookingProfile.legacy_pages.enabled.find_by(slug: params[:slug])
    @profile = profile if profile&.assignment_mode_fixed?
  end

  # Página nova (page_version 2) só é servida pela API v2 (#1188).
  def per_agent_legacy_profile(profile)
    profile if profile&.enabled? && profile.legacy_page? && profile.assignment_mode_per_agent?
  end

  # For #confirm the token is the real authorization, but we still bind it to the
  # :slug context so a token minted for one profile/link can't be replayed against
  # another (defense in depth). A missing/disabled slug is a generic failure.
  def set_profile_for_confirm
    resolve_booking_context
    return render json: { error: 'booking_failed' }, status: :unprocessable_entity if @profile.blank?

    payload = Crm::Calendar::PublicBookingService.verify_token!(params[:token])
    # Bind the token to BOTH the profile and the per_agent/fixed nature of the
    # context (a per_agent token must resolve a link; a fixed token must not).
    return if payload['p'].to_i == @profile.id &&
              payload['l'].present? == @link.present? &&
              payload['l'].to_i == @link&.id.to_i

    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  rescue ArgumentError
    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  end

  # The agent the booking is attributed to: the link's agent (per_agent) or the
  # profile's default assignee (fixed). Drives per-agent availability + ownership.
  def booking_agent
    @link&.agent || @profile.default_assignee
  end

  def send_verification_email(initiated)
    confirm_url = "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/book/#{booking_slug}/confirm?token=#{CGI.escape(initiated.token)}"
    Crm::BookingVerificationMailer.verify(
      email: initiated.email,
      name: initiated.name,
      agent_name: public_agent_name,
      confirm_url: confirm_url,
      starts_at_label: verification_time_label(initiated.starts_at)
    ).deliver_later
  end

  # The slug the booker actually used (link slug in per_agent mode) so the confirm
  # link round-trips through the same context resolution.
  def booking_slug
    @link&.slug || @profile.slug
  end

  # Public-facing host name: the link's agent (per_agent) or the profile fallback.
  def public_agent_name
    @link&.agent&.name.presence || @profile.public_agent_name
  end

  def verification_time_label(starts_at_iso)
    Time.iso8601(starts_at_iso).in_time_zone(@profile.resolved_timezone).strftime('%d/%m/%Y %H:%M')
  rescue ArgumentError
    starts_at_iso
  end

  def public_profile_payload
    {
      slug: booking_slug,
      agent_name: public_agent_name,
      title: @profile.title,
      description: @profile.description,
      duration_minutes: @profile.duration_minutes,
      timezone: @profile.resolved_timezone,
      booking_window_days: @profile.booking_window_days
    }
  end

  def sanitized_date
    raw = params[:date].to_s
    return unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(raw).to_s
  rescue ArgumentError
    nil
  end

  def booking_params
    params.permit(:name, :email, :starts_at, :company, :form_loaded_at)
  end

  # Honeypot: a hidden field ("company") that a human never fills.
  def honeypot_tripped?
    params[:company].present?
  end

  # Time-trap: reject submissions that arrive implausibly fast (bot) — the page
  # stamps form_loaded_at (epoch ms) when it renders the form.
  def time_trap_tripped?
    loaded_at = params[:form_loaded_at].to_i
    return false if loaded_at.zero?

    (Time.current.to_i * 1000) - loaded_at < 2000
  end

  # Bots get the same generic success-less envelope; never reveal the trap.
  def render_bot_rejected
    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  end

  def render_generic_error(error)
    Rails.logger.error("Public booking error: #{error.class.name}")
    render json: { error: 'booking_failed' }, status: :unprocessable_entity
  end
end
