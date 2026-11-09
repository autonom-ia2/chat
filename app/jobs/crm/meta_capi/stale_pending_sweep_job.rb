# Ends the sends to Meta that stopped midway (#2799). A process that dies during the POST
# (deploy, out of memory) or a database gone while releasing the row leaves it `pending`.
# Nobody posts it again (Meta does not dedup), and Crm::MetaConversionEvent.claim only ends it
# when a retry comes, so without this sweep the card would say "sending now" forever.
#
# Scheduled without an account (config/schedule.yml), it enqueues one run per account that has
# an old pending row; each run ends at most BATCH_SIZE of them as an unknown outcome
# ("we do not know if the notice arrived"). The next round takes the rest.
class Crm::MetaCapi::StalePendingSweepJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 500

  def perform(account_id = nil)
    return Crm::MetaConversionEvent.end_stale_pending!(account_id, limit: BATCH_SIZE) if account_id

    Crm::MetaConversionEvent.stale_pending.distinct.pluck(:account_id).each { |id| self.class.perform_later(id) }
  end
end
