# Step 2 of a search by conversation (#2277): reads ONE wave of batches and requeues itself for the next.
#
# The state lives in the database, not in the job: a search stopped by the person, by the ceiling or by the AI
# resumes from the pending batches, and a done batch is never paid again. One search per account reads at a time
# (ConversationAudience::Semaphore); the others wait queued and try again every QUEUED_RETRY. Status changes are
# conditional updates, so a "Parar" clicked during a wave is never overwritten by the job.
#
# One chain of jobs per search: each start or resume gives the search a new run_token
# (ConversationAudienceSearch.queue!), every job carries it, and a job whose token is no longer the search's ends
# without touching anything — no requeue, no slot given back. Only the current chain gives the slot back.
class ConversationAudience::ReadJob < ApplicationJob
  queue_as :low

  BETWEEN_WAVES = 1.second
  # A batch failed and is read again: the pause lets an AI that was out (429, 5xx) come back.
  RETRY_WAIT = 30.seconds
  QUEUED_RETRY = 15.seconds
  # Covers a whole wave with room to spare; if the process dies, the lock expires by itself.
  LOCK_TTL = 6.minutes

  def self.lock_key(search_id)
    "conversation_audience:search:#{search_id}"
  end

  def perform(search_id, token)
    search = ConversationAudienceSearch.find_by(id: search_id)
    return unless current?(search, token)
    return ConversationAudience::Semaphore.leave(search) unless search.running?

    ran = false
    Redis::LockManager.new.with_lock(self.class.lock_key(search.id), LOCK_TTL.to_i) do
      ran = true
      read(search.reload, token)
    end
    # The lock is busy (a wave of an older chain still in flight): this chain tries again in a moment.
    self.class.set(wait: QUEUED_RETRY).perform_later(search.id, token) unless ran
  end

  private

  def current?(search, token)
    search.present? && token.present? && search.run_token == token
  end

  def read(search, token)
    return unless current?(search, token)
    return ConversationAudience::Semaphore.leave(search) unless search.running?

    credential = credential_for(search, token)
    return if credential.nil?
    return wait_in_line(search, token) unless ConversationAudience::Semaphore.enter(search)
    return ConversationAudience::Semaphore.leave(search) unless reading!(search, token)

    after(search, token, ConversationAudience::Wave.new(search, credential: credential).run)
  rescue StandardError => e
    # Class and place only: the message of an AI error may echo the conversations.
    Rails.logger.error("[conversation_audience][read] search=#{search.id} #{e.class.name}\n#{Array(e.backtrace).first(5).join("\n")}")
    finish(search, token, ConversationAudienceSearch::FAILED, error: 'error')
  end

  # The person may still read the conversations, and the account still has its key; otherwise the search ends here
  # (-> nil).
  def credential_for(search, token)
    error = ConversationAudience::Access::ERROR unless ConversationAudience::Access.allowed?(search)
    credential = ConversationAudience::Credential.for(search.account) if error.nil?
    error ||= 'no_key' if credential.nil?
    finish(search, token, ConversationAudienceSearch::FAILED, error: error) if error
    credential
  end

  def after(search, token, outcome)
    case outcome
    when ConversationAudience::Wave::CONTINUE then self.class.set(wait: BETWEEN_WAVES).perform_later(search.id, token)
    when ConversationAudience::Wave::RETRY then self.class.set(wait: RETRY_WAIT).perform_later(search.id, token)
    when ConversationAudience::Wave::DONE then finish(search, token, ConversationAudienceSearch::DONE)
    when ConversationAudience::Wave::CEILING then finish(search, token, ConversationAudienceSearch::CEILING)
    else finish(search, token, ConversationAudienceSearch::FAILED, error: 'ai_error')
    end
  end

  # The heartbeat moves while it waits too: a search without a heartbeat is the one whose job was lost.
  def wait_in_line(search, token)
    search.update!(heartbeat_at: Time.current)
    self.class.set(wait: QUEUED_RETRY).perform_later(search.id, token)
  end

  def reading!(search, token)
    ConversationAudienceSearch.move(search.id, from: ConversationAudienceSearch::RUNNING, to: ConversationAudienceSearch::READING,
                                               token: token, started_at: search.started_at || Time.current, heartbeat_at: Time.current)
  end

  # Only the chain the search still belongs to ends it: a wave of an older chain that finishes after a "Parar" and
  # "Continuar" changes nothing (the new chain reads on, with the ceiling the person agreed to).
  def finish(search, token, status, error: nil)
    return unless ConversationAudienceSearch.exists?(id: search.id, run_token: token)

    ConversationAudience::Semaphore.leave(search)
    moved = ConversationAudienceSearch.move(search.id, from: ConversationAudienceSearch::RUNNING, to: status, token: token,
                                                       error: error, finished_at: Time.current)
    ConversationAudience::Bell.ring(search.reload) if moved
  end
end
