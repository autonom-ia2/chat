# A slice of the conversations of a search for one reader call (#2277). done is never read again: a resumed search
# goes on from the pending ones, and the account never pays for the same batch twice. skipped is a batch the AI could
# not read after ConversationAudience::Wave::MAX_ATTEMPTS (an answer it could not give for those conversations): the
# search goes on without it and the screen says how many conversations were left unread.
class ConversationAudienceBatch < ApplicationRecord
  PENDING = 'pending'.freeze
  DONE = 'done'.freeze
  SKIPPED = 'skipped'.freeze
  STATUSES = [PENDING, DONE, SKIPPED].freeze

  belongs_to :search, class_name: 'ConversationAudienceSearch', inverse_of: :batches

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }
  scope :skipped, -> { where(status: SKIPPED) }
end
