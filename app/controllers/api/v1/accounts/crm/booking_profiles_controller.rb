# Admin-only management API for the public booking profiles (P3 slice S6). One
# profile per calendar-enabled inbox. Gated by the calendar-meetings feature flag
# AND the AgentBookingProfile policy (administrator-only). Returns the PUBLIC
# booking URL (FRONTEND_URL + /book/:slug) so an admin can copy/share it.
class Api::V1::Accounts::Crm::BookingProfilesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_calendar_meetings_enabled
  before_action :fetch_profile, only: [:update, :destroy, :agent_links, :upsert_agent_link, :destroy_agent_link]

  def index
    authorize ::Crm::AgentBookingProfile
    profiles = policy_scope(::Crm::AgentBookingProfile).legacy_pages
                                                       .includes(:inbox, :default_pipeline, :default_stage, :default_assignee)
                                                       .order(:id)
    render json: { payload: profiles.map { |profile| serialize(profile) } }
  end

  def create
    authorize ::Crm::AgentBookingProfile
    @profile = Current.account.crm_agent_booking_profiles.new(profile_params.merge(inbox_id: validated_inbox_id))
    @profile.save!
    apply_calendar_shared!
    render json: { payload: serialize(@profile) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.first || 'Invalid booking profile' }, status: :unprocessable_entity
  end

  def update
    authorize @profile
    @profile.update!(profile_params.except(:inbox_id))
    apply_calendar_shared!
    render json: { payload: serialize(@profile) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.first || 'Invalid booking profile' }, status: :unprocessable_entity
  end

  def destroy
    authorize @profile
    @profile.destroy!
    head :no_content
  end

  # GET .../booking_profiles/:id/agent_links — the agents eligible for a per-agent
  # link (members of the profile's calendar mailbox) + their current link, if any.
  def agent_links
    authorize @profile, :show?
    render json: { payload: eligible_agents_payload }
  end

  # POST .../booking_profiles/:id/agent_links — create/update a per-agent link for
  # { agent_id, inbox_id } and return its public URL.
  def upsert_agent_link
    authorize @profile, :update?
    link = @profile.agent_booking_links.find_or_initialize_by(agent_id: agent_link_params[:agent_id])
    link.account = Current.account
    link.inbox_id = agent_link_params[:inbox_id].presence || @profile.inbox_id
    link.enabled = true
    link.save!
    render json: { payload: serialize_link(link) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.first || 'Invalid booking link' }, status: :unprocessable_entity
  end

  # DELETE .../booking_profiles/:id/agent_links/:link_id
  def destroy_agent_link
    authorize @profile, :update?
    @profile.agent_booking_links.find(params[:link_id]).destroy!
    head :no_content
  end

  private

  # When the admin toggles "shared calendar", flip it on the profile's mailbox
  # channel (it is a property of the mailbox, shared across profiles).
  def apply_calendar_shared!
    return if params.dig(:booking_profile, :calendar_shared).nil?

    channel = @profile.inbox&.channel
    channel.update!(calendar_shared: ActiveModel::Type::Boolean.new.cast(params[:booking_profile][:calendar_shared])) if channel.is_a?(Channel::Email)
  end

  def eligible_agents_payload
    ensure_agent_links! if @profile.assignment_mode_per_agent?
    links_by_agent = @profile.agent_booking_links.index_by(&:agent_id)
    @profile.inbox.inbox_members.includes(:user).filter_map do |member|
      user = member.user
      next if user.blank?

      { agent_id: user.id, agent_name: user.name, agent_email: user.email, link: serialize_link(links_by_agent[user.id]) }
    end
  end

  # Pre-generate a link for every eligible agent (mailbox member) that lacks one, so
  # the admin sees a ready-to-copy link for each — no manual "generate" step. Idempotent.
  def ensure_agent_links!
    existing = @profile.agent_booking_links.pluck(:agent_id)
    (@profile.inbox.inbox_members.pluck(:user_id).uniq - existing).each do |uid|
      @profile.agent_booking_links.create(account: Current.account, agent_id: uid, inbox_id: @profile.inbox_id, enabled: true)
    end
  end

  def ensure_calendar_meetings_enabled
    render json: { error: 'crm.calendar_meetings.disabled' }, status: :not_found unless Crm::Config.calendar_meetings_enabled?(Current.account)
  end

  def fetch_profile
    # Páginas novas (page_version 2) são da BookingPagesController; a gaveta antiga não as vê nem edita.
    @profile = Current.account.crm_agent_booking_profiles.legacy_pages.find(params[:id])
  end

  def validated_inbox_id
    inbox = Current.account.inboxes.find(profile_params[:inbox_id])
    channel = inbox.channel
    unless channel.is_a?(Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
      raise ActiveRecord::RecordInvalid, Crm::AgentBookingProfile.new.tap { |p| p.errors.add(:inbox, 'is not a calendar-enabled inbox') }
    end

    inbox.id
  end

  def profile_params
    parameter_set(:booking_profile).permit(
      :inbox_id, :title, :description, :duration_minutes, :buffer_minutes,
      :booking_window_days, :timezone, :enabled, :assignment_mode,
      :default_pipeline_id, :default_stage_id, :default_assignee_id,
      working_hours: [:start_hour, :end_hour, { weekdays: [] }]
    )
  end

  def agent_link_params
    parameter_set(:agent_link).permit(:agent_id, :inbox_id)
  end

  def serialize_link(link)
    return nil if link.blank?

    {
      id: link.id,
      agent_id: link.agent_id,
      inbox_id: link.inbox_id,
      slug: link.slug,
      enabled: link.enabled,
      public_url: "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/book/#{link.slug}"
    }
  end

  def serialize(profile)
    {
      id: profile.id,
      inbox_id: profile.inbox_id,
      inbox_name: profile.inbox&.name,
      slug: profile.slug,
      public_url: public_url(profile),
      title: profile.title,
      description: profile.description,
      duration_minutes: profile.duration_minutes,
      buffer_minutes: profile.buffer_minutes,
      booking_window_days: profile.booking_window_days,
      working_hours: profile.working_hours,
      timezone: profile.resolved_timezone,
      enabled: profile.enabled,
      assignment_mode: profile.assignment_mode,
      calendar_shared: calendar_shared?(profile),
      default_pipeline_id: profile.default_pipeline_id,
      default_stage_id: profile.default_stage_id,
      default_assignee_id: profile.default_assignee_id,
      created_at: profile.created_at&.iso8601,
      updated_at: profile.updated_at&.iso8601
    }
  end

  def public_url(profile)
    base = ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
    "#{base}/book/#{profile.slug}"
  end

  def calendar_shared?(profile)
    channel = profile.inbox&.channel
    channel.is_a?(Channel::Email) && channel.calendar_shared?
  end
end
