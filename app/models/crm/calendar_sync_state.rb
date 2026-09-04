# Push-notification subscription state for one calendar mailbox (S7-B). See the
# migration for the column semantics. Found by channel_id (the value the provider
# echoes back in its webhook) so an incoming notification resolves to exactly one
# mailbox, and the verification_token authenticates it.
# == Schema Information
#
# Table name: crm_calendar_sync_states
#
#  id                 :bigint           not null, primary key
#  expires_at         :datetime
#  last_notified_at   :datetime
#  metadata           :jsonb            not null
#  provider           :integer          default("google"), not null
#  status             :integer          default("active"), not null
#  verification_token :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  channel_id         :string
#  inbox_id           :bigint
#  resource_id        :string
#
# Indexes
#
#  index_crm_calendar_sync_states_on_account_id  (account_id)
#  index_crm_calendar_sync_states_on_channel_id  (channel_id)
#  index_crm_calendar_sync_states_on_expires_at  (expires_at)
#  index_crm_calendar_sync_states_on_inbox_id    (inbox_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::CalendarSyncState < ApplicationRecord
  self.table_name = 'crm_calendar_sync_states'

  belongs_to :account
  belongs_to :inbox

  enum provider: { google: 0, microsoft: 1 }
  enum status: { active: 0, expired: 1, failed: 2 }, _prefix: true

  scope :renewable, -> { where(status: :active) }

  # Expiring within the threshold (or already past) — the renewal job re-subscribes.
  def self.expiring_before(time)
    where('expires_at IS NULL OR expires_at <= ?', time)
  end

  def channel
    inbox&.channel
  end
end
