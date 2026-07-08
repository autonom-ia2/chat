# == Schema Information
#
# Table name: crm_meetings
#
#  id                  :bigint           not null, primary key
#  description         :text
#  ends_at             :datetime         not null
#  metadata            :jsonb            not null
#  online_meeting_type :integer          default("teams"), not null
#  online_meeting_url  :text
#  outcome             :integer
#  outcome_notes       :text
#  outcome_recorded_at :datetime
#  provider            :integer          not null
#  starts_at           :datetime         not null
#  status              :integer          default("draft"), not null
#  timezone            :string           default("UTC"), not null
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  card_id             :bigint           not null
#  created_by_id       :bigint           not null
#  external_event_id   :string
#  inbox_id            :bigint
#  reminder_id         :bigint
#
# Indexes
#
#  idx_crm_meetings_card                                     (account_id,card_id)
#  idx_crm_meetings_created_by                               (account_id,created_by_id)
#  idx_crm_meetings_external_unique                          (external_event_id,provider) UNIQUE WHERE (external_event_id IS NOT NULL)
#  idx_crm_meetings_inbox                                    (account_id,inbox_id)
#  idx_crm_meetings_starts_at                                (account_id,starts_at)
#  idx_crm_meetings_status                                   (account_id,status)
#  idx_on_account_id_outcome_outcome_recorded_at_085cfbd511  (account_id,outcome,outcome_recorded_at)
#  index_crm_meetings_on_account_id                          (account_id)
#  index_crm_meetings_on_card_id                             (card_id)
#  index_crm_meetings_on_created_by_id                       (created_by_id)
#  index_crm_meetings_on_inbox_id                            (inbox_id)
#  index_crm_meetings_on_reminder_id                         (reminder_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (reminder_id => crm_follow_ups.id) ON DELETE => nullify
#
class Crm::Meeting < ApplicationRecord
  self.table_name = 'crm_meetings'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User'
  belongs_to :reminder, class_name: 'Crm::FollowUp', optional: true

  has_many :meeting_guests, class_name: 'Crm::MeetingGuest', dependent: :destroy, inverse_of: :meeting

  enum status: { draft: 0, scheduled: 1, completed: 2, canceled: 3, rescheduled: 4, no_show: 5, failed: 6 }
  enum provider: { microsoft: 0, google: 1 }
  enum online_meeting_type: { teams: 0, google_meet: 1, no_online: 2 }
  # The `_prefix` keeps these methods (outcome_held?/outcome_no_show?) distinct
  # from the status enum, which already owns `no_show`/`completed` (status_*).
  enum outcome: { held: 0, no_show: 1 }, _prefix: true

  validates :title, :starts_at, :ends_at, :timezone, :provider, presence: true
  # timezone is a NOT-NULL column defaulting to 'UTC'; presence alone let a
  # non-IANA string persist and later collapse date math to a silent UTC. Require
  # a value ActiveSupport::TimeZone can resolve — accepts both IANA identifiers
  # (America/Sao_Paulo) and Rails' friendly names (Brasilia) (H4-booking).
  validate :timezone_must_be_resolvable
  validates :account_id, :card_id, :inbox_id, :created_by_id, presence: true
  validates :external_event_id, uniqueness: { scope: :provider }, allow_blank: true
  validates :metadata, jsonb_attributes_length: true
  validate :ends_at_after_starts_at
  validate :linked_records_must_belong_to_account
  validate :inbox_must_have_calendar_enabled
  validate :card_must_have_email_reachable_guest

  scope :upcoming, -> { where(status: :scheduled).where('starts_at > ?', Time.current) }
  scope :past, -> { where(status: %i[completed canceled no_show]) }
  scope :by_agent, ->(user_id) { where(created_by_id: user_id) }
  # `outcome_held` / `outcome_no_show` scopes are provided by the prefixed enum.
  scope :with_outcome, -> { where.not(outcome: nil) }

  def email_channel
    inbox.channel
  end

  private

  def timezone_must_be_resolvable
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?

    errors.add(:timezone, 'is not a valid time zone')
  end

  def ends_at_after_starts_at
    return if ends_at.blank? || starts_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, 'must be after starts_at')
  end

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:inbox)
    validate_same_account(:reminder)
    validate_created_by_account
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end

  def validate_created_by_account
    return if created_by.blank? || account_id.blank?
    return if created_by.account_users.exists?(account_id: account_id)

    errors.add(:created_by, 'must belong to the same account')
  end

  def inbox_must_have_calendar_enabled
    return if inbox.blank?

    channel = inbox.channel
    return if channel.is_a?(Channel::Email) && channel.calendar_enabled?

    errors.add(:inbox, 'must have calendar enabled')
  end

  def card_must_have_email_reachable_guest
    return if card.blank?

    contact_has_email = card.contact&.email.present?
    guests_have_email = meeting_guests.any? { |guest| guest.email.present? }
    return if contact_has_email || guests_have_email

    errors.add(:base, 'at least one email-reachable guest is required')
  end
end
