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
#  source              :string
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
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (reminder_id => crm_follow_ups.id) ON DELETE => nullify
#
class Crm::Meeting < ApplicationRecord
  self.table_name = 'crm_meetings'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :inbox, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :reminder, class_name: 'Crm::FollowUp', optional: true

  has_many :meeting_guests, class_name: 'Crm::MeetingGuest', dependent: :destroy, inverse_of: :meeting

  enum status: { draft: 0, scheduled: 1, completed: 2, canceled: 3, rescheduled: 4, no_show: 5, failed: 6 }
  # `internal` = reunião sem provedor de calendário (WhatsApp, link do agente, presencial). Enum é inteiro:
  # valor novo não pede migration.
  enum provider: { microsoft: 0, google: 1, internal: 2 }
  enum online_meeting_type: { teams: 0, google_meet: 1, no_online: 2, whatsapp_video: 3, whatsapp_voice: 4, custom_link: 5, in_person: 6 }
  # The `_prefix` keeps these methods (outcome_held?/outcome_no_show?) distinct
  # from the status enum, which already owns `no_show`/`completed` (status_*).
  enum outcome: { held: 0, no_show: 1 }, _prefix: true

  validates :title, :starts_at, :ends_at, :timezone, :provider, presence: true
  validates :account_id, :card_id, :created_by_id, presence: true
  validates :inbox_id, presence: true, unless: :internal?
  validates :external_event_id, uniqueness: { scope: :provider }, allow_blank: true
  validates :metadata, jsonb_attributes_length: true
  validate :ends_at_after_starts_at
  validate :linked_records_must_belong_to_account
  validate :inbox_must_have_calendar_enabled
  validate :card_must_have_reachable_guest
  validate :custom_link_must_be_web_url

  scope :upcoming, -> { where(status: :scheduled).where('starts_at > ?', Time.current) }
  scope :past, -> { where(status: %i[completed canceled no_show]) }
  scope :by_agent, ->(user_id) { where(created_by_id: user_id) }
  # `outcome_held` / `outcome_no_show` scopes are provided by the prefixed enum.
  scope :with_outcome, -> { where.not(outcome: nil) }

  def email_channel
    inbox&.channel
  end

  private

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
    return if inbox.blank? || internal?

    channel = inbox.channel
    return if channel.is_a?(Channel::Email) && channel.calendar_enabled?

    errors.add(:inbox, 'must have calendar enabled')
  end

  # Reunião de calendário (Google/Microsoft) precisa de convidado com e-mail: o convite sai pelo provedor.
  # Reunião interna basta ter como falar com alguém: e-mail OU telefone (WhatsApp).
  def card_must_have_reachable_guest
    return if card.blank? || reachable_guest?

    errors.add(:base, internal? ? 'at least one reachable guest (email or phone) is required' : 'at least one email-reachable guest is required')
  end

  def reachable_guest?
    return true if email_reachable?

    internal? && phone_reachable?
  end

  def email_reachable?
    card.contact&.email.present? || meeting_guests.any? { |guest| guest.email.present? }
  end

  def phone_reachable?
    card.contact&.phone_number.present? || meeting_guests.any? { |guest| guest.phone_number.present? }
  end

  # O link do agente vai para um href: só http/https, sem javascript: nem data:.
  def custom_link_must_be_web_url
    return unless custom_link? && online_meeting_url.present?
    return if Crm::WebUrl.valid?(online_meeting_url)

    errors.add(:online_meeting_url, 'must be an http or https URL')
  end
end
