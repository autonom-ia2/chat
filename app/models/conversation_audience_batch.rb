# A slice of the conversations of a search for one reader call (#2277). done is never read again: a resumed search
# goes on from the pending ones, and the account never pays for the same batch twice.
class ConversationAudienceBatch < ApplicationRecord
  PENDING = 'pending'.freeze
  DONE = 'done'.freeze
  STATUSES = [PENDING, DONE].freeze

  belongs_to :search, class_name: 'ConversationAudienceSearch', inverse_of: :batches

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }
end
