# Step 2 of a search by conversation (#2277): reads ONE wave of batches and requeues itself for the next.
#
# The state lives in the database, not in the job: a search stopped by the person, by the ceiling or by the AI
# resumes from the pending batches, and a done batch is never paid again. One search per account reads at a time
# (ConversationAudience::Semaphore); the others wait queued and try again every QUEUED_RETRY. Status changes are
# conditional updates, so a "Parar" clicked during a wave is never overwritten by the job.
class ConversationAudience::ReadJob < ApplicationJob
  queue_as :low

  BETWEEN_WAVES = 1.second
  QUEUED_RETRY = 15.seconds
  # Covers a whole wave with room to spare; if the process dies, the lock expires by itself.
  LOCK_TTL = 6.minutes

  def perform(search_id)
    search = ConversationAudienceSearch.find_by(id: search_id)
    return if search.nil?
    return ConversationAudience::Semaphore.leave(search) unless search.running?

    ran = false
    Redis::LockManager.new.with_lock("conversation_audience:search:#{search.id}", LOCK_TTL.to_i) do
      ran = true
      read(search.reload)
    end
    # Another job holds this search (a wave in flight): it goes on from there; this one tries again in a moment.
    self.class.set(wait: QUEUED_RETRY).perform_later(search.id) unless ran
  end

  private

  def read(search)
    return ConversationAudience::Semaphore.leave(search) unless search.running?

    credential = ConversationAudience::Credential.for(search.account)
    return finish(search, ConversationAudienceSearch::FAILED, error: 'no_key') if credential.nil?
    return wait_in_line(search) unless ConversationAudience::Semaphore.enter(search)
    return ConversationAudience::Semaphore.leave(search) unless reading!(search)

    after(search, ConversationAudience::Wave.new(search, credential: credential).run)
  rescue StandardError => e
    Rails.logger.error("[conversation_audience][read] search=#{search.id} #{e.class}: #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}")
    finish(search, ConversationAudienceSearch::FAILED, error: 'error')
  end

  def after(search, outcome)
    case outcome
    when ConversationAudience::Wave::CONTINUE then self.class.set(wait: BETWEEN_WAVES).perform_later(search.id)
    when ConversationAudience::Wave::DONE then finish(search, ConversationAudienceSearch::DONE)
    when ConversationAudience::Wave::CEILING then finish(search, ConversationAudienceSearch::CEILING)
    else finish(search, ConversationAudienceSearch::FAILED, error: 'ai_error')
    end
  end

  # The heartbeat moves while it waits too: a search without a heartbeat is the one whose job was lost.
  def wait_in_line(search)
    search.update!(heartbeat_at: Time.current)
    self.class.set(wait: QUEUED_RETRY).perform_later(search.id)
  end

  def reading!(search)
    ConversationAudienceSearch.move(search.id, from: ConversationAudienceSearch::RUNNING, to: ConversationAudienceSearch::READING,
                                               started_at: search.started_at || Time.current, heartbeat_at: Time.current)
  end

  def finish(search, status, error: nil)
    ConversationAudience::Semaphore.leave(search)
    moved = ConversationAudienceSearch.move(search.id, from: ConversationAudienceSearch::RUNNING, to: status, error: error,
                                                       finished_at: Time.current)
    ConversationAudience::Bell.ring(search.reload) if moved
  end
end
