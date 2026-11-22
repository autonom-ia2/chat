# A ringing inbound call holds off its conversation's auto-assignment, so the agent who answers gets it;
# see Enterprise::Conversation#call_ringing?
module Concerns::CallAssignmentHold
  extend ActiveSupport::Concern

  included do
    # A call still ringing past Twilio's dial limit lost its end callback, so it holds nothing
    scope :holding_assignment, lambda {
      incoming.where(status: 'ringing', created_at: Voice::RingNextAgentJob::MAX_RING_SECONDS.seconds.ago..)
    }

    # Fork (upgrade 4.20.1, #3120): a WhatsApp call holds nothing, as on the fork; see Inbox#rings_for_calls?
    after_update_commit -> { conversation.auto_assign_after_call },
                        if: -> { inbox.rings_for_calls? && incoming? && terminal? && status_before_last_save == 'ringing' }
  end
end
