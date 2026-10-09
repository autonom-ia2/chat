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
#  page_version        :integer          default(1), not null
#  default_pipeline_id :bigint
#  default_stage_id    :bigint
#  inbox_id            :bigint
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
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::AgentBookingProfile < ApplicationRecord
  self.table_name = 'crm_agent_booking_profiles'

  DEFAULT_WORKING_HOURS = { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [1, 2, 3, 4, 5] }.freeze
  MIN_DURATION = 5
  MAX_DURATION = 480
  MAX_BUFFER = 240
  MIN_WINDOW = 1
  MAX_WINDOW = 90
  LEGACY_PAGE = 1
  NEW_PAGE = 2
  MAX_MIN_NOTICE = 14 * 24 * 60
  MAX_EXTRA_DURATIONS = 5
  LOCATION_TYPES = %w[whatsapp_video whatsapp_voice custom_link in_person google_meet teams].freeze
  TEMPLATE_KEYS = %w[sales_30 consult_45 visit_60 blank].freeze
  HEX_DIGITS = '0123456789abcdefABCDEF'.freeze
  MAX_LOCATIONS = 6
  MAX_TEXT = 500
  MAX_IMAGE_BYTES = 2.megabytes
  IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze

  # fixed     -> one default_assignee owns every booking (original S6 behaviour).
  # per_agent -> each eligible agent shares their OWN link (agent_booking_links);
  #              a booking through a link is attributed to that agent.
  enum assignment_mode: { fixed: 0, per_agent: 1 }, _prefix: true

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :default_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :default_assignee, class_name: 'User', optional: true
  has_many :agent_booking_links, class_name: 'Crm::AgentBookingLink',
                                 foreign_key: :booking_profile_id, inverse_of: :booking_profile, dependent: :destroy

  before_validation :ensure_slug, on: :create
  before_validation :normalize_working_hours
  before_validation :normalize_json_settings

  validates :slug, presence: true, uniqueness: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_DURATION, less_than_or_equal_to: MAX_DURATION }
  validates :buffer_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_BUFFER }
  validates :booking_window_days, numericality: { only_integer: true, greater_than_or_equal_to: MIN_WINDOW, less_than_or_equal_to: MAX_WINDOW }
  validates :title, length: { maximum: 255 }, allow_blank: true
  validates :metadata, jsonb_attributes_length: true
  # Página antiga (1) continua amarrada a uma caixa de calendário; a nova (2) funciona sem caixa.
  validates :inbox, presence: true, if: :legacy_page?
  validate :inbox_must_belong_to_account
  validate :new_page_settings_must_be_sane
  validate :default_refs_must_belong_to_account
  validate :working_hours_must_be_sane
  # An ENABLED profile in FIXED mode must resolve a real scheduling user — Crm::Meeting
  # requires created_by and a public booking has no User of its own. In per_agent mode
  # the host comes from each agent's link, so default_assignee is optional there.
  validates :default_assignee_id, presence: true, if: -> { enabled? && assignment_mode_fixed? }

  scope :enabled, -> { where(enabled: true) }
  scope :legacy_pages, -> { where(page_version: LEGACY_PAGE) }
  scope :new_pages, -> { where(page_version: NEW_PAGE) }

  has_one_attached :logo
  has_one_attached :photo

  def legacy_page?
    page_version == LEGACY_PAGE
  end

  def new_page?
    page_version == NEW_PAGE
  end

  # Durações que o cliente pode escolher: a principal e as extras, sem repetir, da menor para a maior.
  def durations
    ([duration_minutes] + Array(slot_durations).map(&:to_i)).uniq.sort
  end

  def resolved_timezone
    Crm::Timezone::Resolver.new(explicit: timezone, account: account).name_or_default
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

  # jsonb vindo com chave símbolo só vira string depois de salvar: normaliza antes, para a validação ver o que vai
  # ser gravado.
  def normalize_json_settings
    self.brand = brand.deep_stringify_keys if brand.is_a?(Hash)
    self.locations = locations.map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : item } if locations.is_a?(Array)
  end

  def normalize_working_hours
    self.working_hours = DEFAULT_WORKING_HOURS.dup if working_hours.blank?
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

  def new_page_settings_must_be_sane
    return unless new_page?

    validate_locations
    validate_slot_durations
    validate_min_notice
    validate_brand
    validate_contact_phone
    validate_images
  end

  def validate_locations
    list = locations
    return errors.add(:locations, 'must be a list') unless list.is_a?(Array)
    return errors.add(:locations, 'has too many items') if list.size > MAX_LOCATIONS

    list.each { |location| validate_location(location) }
  end

  def validate_location(location)
    return errors.add(:locations, 'item must be an object') unless location.is_a?(Hash)
    return errors.add(:locations, 'unknown type') unless LOCATION_TYPES.include?(location['type'])
    return if location['type'] != 'custom_link'

    errors.add(:locations, 'link must be an http or https URL') unless Crm::WebUrl.valid?(location['url'], max: MAX_TEXT)
  end

  def validate_slot_durations
    list = slot_durations
    ok = list.is_a?(Array) && list.size <= MAX_EXTRA_DURATIONS && list.all? { |v| v.is_a?(Integer) && v.between?(MIN_DURATION, MAX_DURATION) }
    errors.add(:slot_durations, 'invalid durations') unless ok
  end

  def validate_min_notice
    return if min_notice_minutes.to_i.between?(0, MAX_MIN_NOTICE)

    errors.add(:min_notice_minutes, 'out of range')
  end

  def validate_brand
    return errors.add(:brand, 'must be an object') unless brand.is_a?(Hash)

    color = brand['color']
    errors.add(:brand, 'invalid color') if color.present? && !hex_color?(color)
    errors.add(:brand, 'headline too long') if brand['headline'].to_s.length > MAX_TEXT
  end

  def hex_color?(value)
    value.is_a?(String) && value.length == 7 && value.start_with?('#') && value.delete_prefix('#').chars.all? { |char| HEX_DIGITS.include?(char) }
  end

  # Logo e foto vão para a página pública: só PNG, JPEG ou WebP (SVG pode carregar script) e até 2 MB.
  def validate_images
    %i[logo photo].each do |name|
      attachment = public_send(name)
      next unless attachment.attached?

      errors.add(name, 'must be a PNG, JPEG or WebP image') unless IMAGE_TYPES.include?(attachment.content_type)
      errors.add(name, 'is too large') if attachment.byte_size > MAX_IMAGE_BYTES
    end
  end

  def validate_contact_phone
    return if contact_phone.blank?
    return if contact_phone.start_with?('+') && TelephoneNumber.valid?(contact_phone)

    errors.add(:contact_phone, 'must be a valid E.164 number')
  end

  def working_hours_must_be_sane
    return if start_hour.between?(0, 23) && end_hour.between?(1, 24) && start_hour < end_hour

    errors.add(:working_hours, 'invalid working hours')
  end
end
