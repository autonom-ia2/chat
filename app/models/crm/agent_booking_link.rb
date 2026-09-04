# A per-agent public booking link (P3 slice S6, per_agent mode). Belongs to a
# booking profile (which carries the shared config: duration, working hours, window,
# funnel) but binds its OWN { agent, calendar mailbox }. The opaque `slug`
# (SecureRandom.uuid) is resolved SERVER-SIDE to that agent — a public visitor can
# never change which seller a booking is attributed to. A booking through this link
# is owned/hosted by `agent` and lands on `inbox`'s calendar, with availability
# computed for `agent` (see Crm::Meetings::AvailabilityService).
# == Schema Information
#
# Table name: crm_agent_booking_links
#
#  id                 :bigint           not null, primary key
#  enabled            :boolean          default(TRUE), not null
#  metadata           :jsonb            not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_id           :bigint           not null
#  booking_profile_id :bigint           not null
#  inbox_id           :bigint
#
# Indexes
#
#  idx_crm_booking_links_profile_agent                  (booking_profile_id,agent_id) UNIQUE
#  index_crm_agent_booking_links_on_account_id          (account_id)
#  index_crm_agent_booking_links_on_agent_id            (agent_id)
#  index_crm_agent_booking_links_on_booking_profile_id  (booking_profile_id)
#  index_crm_agent_booking_links_on_inbox_id            (inbox_id)
#  index_crm_agent_booking_links_on_slug                (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (booking_profile_id => crm_agent_booking_profiles.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::AgentBookingLink < ApplicationRecord
  self.table_name = 'crm_agent_booking_links'

  belongs_to :account
  belongs_to :booking_profile, class_name: 'Crm::AgentBookingProfile', inverse_of: :agent_booking_links
  belongs_to :agent, class_name: 'User'
  belongs_to :inbox

  before_validation :ensure_slug, on: :create

  validates :slug, presence: true, uniqueness: true
  validates :agent_id, uniqueness: { scope: :booking_profile_id }
  validate :records_must_belong_to_account
  validate :inbox_must_be_calendar_enabled
  validate :agent_must_be_member_of_inbox

  scope :enabled, -> { where(enabled: true) }

  private

  def ensure_slug
    self.slug ||= SecureRandom.uuid
  end

  def records_must_belong_to_account
    return if account_id.blank?

    errors.add(:booking_profile, 'must belong to the same account') if booking_profile && booking_profile.account_id != account_id
    errors.add(:agent, 'must belong to the same account') if agent && !account.users.exists?(id: agent_id)
    errors.add(:inbox, 'must belong to the same account') if inbox && inbox.account_id != account_id
  end

  def inbox_must_be_calendar_enabled
    return if inbox.blank?

    channel = inbox.channel
    return if channel.is_a?(Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)

    errors.add(:inbox, 'is not a calendar-enabled inbox')
  end

  # Eligibility: an agent can only have a link on a mailbox they are a member of —
  # otherwise we'd hand out a booking link for a calendar the agent cannot host on.
  def agent_must_be_member_of_inbox
    return if inbox.blank? || agent_id.blank?
    return if inbox.inbox_members.exists?(user_id: agent_id)

    errors.add(:agent, 'is not a member of the selected inbox')
  end
end
