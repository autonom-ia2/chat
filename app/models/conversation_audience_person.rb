# Someone the readers found for a search (#2277): one row per contact. A contact with several conversations keeps
# the strongest group (sure > likely > near), with the reason and proofs of the conversation that gave it.
class ConversationAudiencePerson < ApplicationRecord
  SURE = 'certeza'.freeze
  LIKELY = 'provavel'.freeze
  NEAR = 'fora'.freeze
  GROUPS = [SURE, LIKELY, NEAR].freeze

  belongs_to :search, class_name: 'ConversationAudienceSearch', inverse_of: :people
  belongs_to :contact
  belongs_to :conversation

  validates :group, inclusion: { in: GROUPS }

  def self.stronger?(group, than)
    GROUPS.index(group) < GROUPS.index(than)
  end
end
