# Public, Calendly-style booking profile (P3 slice S6). One per calendar-enabled
# inbox. The `slug` is an unguessable SecureRandom.uuid and is the ONLY thing a
# public visitor presents — no account_id is ever trusted from the URL. A disabled
# profile (or unknown slug) is treated as not-found so there is no enumeration and
# no PII leak.
# == Schema Information
#
# Table name: crm_agent_booking_profiles
#
#  id                  :bigint           not null, primary key
#  assignment_mode     :integer          default("fixed"), not null
#  booking_window_days :integer          default(14), not null
#  buffer_minutes      :integer          default(0), not null
#  description         :text
#  duration_minutes    :integer          default(30), not null
#  enabled             :boolean          default(TRUE), not null
#  metadata            :jsonb            not null
#  slug                :string           not null
#  timezone            :string
#  title               :string
#  working_hours       :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  default_assignee_id :bigint
#  default_pipeline_id :bigint
#  default_stage_id    :bigint
#  inbox_id            :bigint           not null
#
# Indexes
#
#  index_crm_agent_booking_profiles_on_account_id  (account_id)
#  index_crm_agent_booking_profiles_on_inbox_id    (inbox_id)
#  index_crm_agent_booking_profiles_on_slug        (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Crm::AgentBookingProfile < ApplicationRecord
  self.table_name = 'crm_agent_booking_profiles'

  DEFAULT_WORKING_HOURS = { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [1, 2, 3, 4, 5] }.freeze
  MIN_DURATION = 5
  MAX_DURATION = 480
  MAX_BUFFER = 240
  MIN_WINDOW = 1
  MAX_WINDOW = 90

  # fixed     -> one default_assignee owns every booking (original S6 behaviour).
  # per_agent -> each eligible agent shares their OWN link (agent_booking_links);
  #              a booking through a link is attributed to that agent.
  enum assignment_mode: { fixed: 0, per_agent: 1 }, _prefix: true

  belongs_to :account
  belongs_to :inbox
  belongs_to :default_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :default_assignee, class_name: 'User', optional: true
  has_many :agent_booking_links, class_name: 'Crm::AgentBookingLink',
                                 foreign_key: :booking_profile_id, inverse_of: :booking_profile, dependent: :destroy

  before_validation :ensure_slug, on: :create
  before_validation :normalize_working_hours

  validates :slug, presence: true, uniqueness: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_DURATION, less_than_or_equal_to: MAX_DURATION }
  validates :buffer_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_BUFFER }
  validates :booking_window_days, numericality: { only_integer: true, greater_than_or_equal_to: MIN_WINDOW, less_than_or_equal_to: MAX_WINDOW }
  validates :title, length: { maximum: 255 }, allow_blank: true
  # The profile timezone anchors every public slot. A non-IANA value used to
  # silently collapse to UTC (shifting a BR 09:00 window to 06:00 BRT); reject it
  # at the boundary. Blank is allowed — resolution then falls through to the
  # account operational tz / ENV default (H4-booking). Accepts both IANA
  # identifiers and Rails' friendly names.
  validate :timezone_must_be_resolvable
  validates :metadata, jsonb_attributes_length: true
  validate :inbox_must_belong_to_account
  validate :default_refs_must_belong_to_account
  validate :working_hours_must_be_sane
  # An ENABLED profile in FIXED mode must resolve a real scheduling user — Crm::Meeting
  # requires created_by and a public booking has no User of its own. In per_agent mode
  # the host comes from each agent's link, so default_assignee is optional there.
  validates :default_assignee_id, presence: true, if: -> { enabled? && assignment_mode_fixed? }

  scope :enabled, -> { where(enabled: true) }

  # Operational timezone resolution for public booking. The operator's explicit
  # profile timezone is the primary source; when blank/invalid it falls through
  # to the shared TimeZoneResolver chain (inbox non-UTC -> account -> ENV default
  # -> :none). Returns a TimeZoneResolver::Resolution so callers can fail-closed
  # on `source: :none` instead of silently anchoring slots to UTC.
  def timezone_resolution
    explicit = ActiveSupport::TimeZone[timezone.to_s] if timezone.present?
    return TimeZoneResolver::Resolution.new(zone: explicit, source: :profile) if explicit

    TimeZoneResolver.for(account: account, inbox: inbox)
  end

  # Zone NAME for display/labels. NEVER nil (falls back to UTC when unresolved),
  # so it stays safe for rendering; scheduling/window callers must use
  # `timezone_resolution` and honor `:none` (fail-closed).
  def resolved_timezone
    timezone_resolution.zone.name
  end

  def start_hour
    working_hours.to_h.fetch('start_hour', DEFAULT_WORKING_HOURS['start_hour']).to_i
  end

  def end_hour
    working_hours.to_h.fetch('end_hour', DEFAULT_WORKING_HOURS['end_hour']).to_i
  end

  # Allowed weekdays as Integers (0=Sunday .. 6=Saturday, Ruby Date#wday convention).
  def weekdays
    raw = working_hours.to_h.fetch('weekdays', DEFAULT_WORKING_HOURS['weekdays'])
    Array(raw).map(&:to_i).select { |d| d.between?(0, 6) }.uniq
  end

  # Agent display name shown publicly. Falls back to the profile title, never the
  # inbox email or any internal id.
  def public_agent_name
    default_assignee&.name.presence || title.presence || inbox&.name.presence
  end

  private

  def ensure_slug
    self.slug ||= SecureRandom.uuid
  end

  def normalize_working_hours
    self.working_hours = DEFAULT_WORKING_HOURS.dup if working_hours.blank?
  end

  def timezone_must_be_resolvable
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?

    errors.add(:timezone, 'is not a valid time zone')
  end

  def inbox_must_belong_to_account
    return if inbox.blank? || account_id.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox, 'must belong to the same account')
  end

  # Defense in depth against cross-account references: the default pipeline/stage/
  # assignee MUST belong to THIS account (and the stage to that pipeline). A public
  # booking creates a card + meeting from these defaults with NO user/Pundit in the
  # loop, so a cross-account id here would leak the booking into another tenant.
  def default_refs_must_belong_to_account
    return if account_id.blank?

    validate_default_pipeline
    validate_default_stage
    validate_default_assignee
  end

  def validate_default_pipeline
    return if default_pipeline_id.blank?
    return if account.crm_pipelines.exists?(id: default_pipeline_id)

    errors.add(:default_pipeline_id, 'must belong to the same account')
  end

  def validate_default_stage
    return if default_stage_id.blank?

    stage = Crm::PipelineStage.find_by(id: default_stage_id)
    return if stage.present? && stage.pipeline&.account_id == account_id &&
              (default_pipeline_id.blank? || stage.pipeline_id == default_pipeline_id)

    errors.add(:default_stage_id, 'must belong to a pipeline in this account')
  end

  def validate_default_assignee
    return if default_assignee_id.blank?
    return if account.users.exists?(id: default_assignee_id)

    errors.add(:default_assignee_id, 'must belong to the same account')
  end

  def working_hours_must_be_sane
    return if start_hour.between?(0, 23) && end_hour.between?(1, 24) && start_hour < end_hour

    errors.add(:working_hours, 'invalid working hours')
  end
end
