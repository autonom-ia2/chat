# How many searches by conversation read at the same time (#2277): one per account and TOTAL in the installation.
# A search over the limit waits in line (queued) and never errors. Each reading search holds one Sidekiq thread
# for a wave of up to 6 reader calls (~20–60 s, at worst one retry of 2 min), hence the installation cap.
#
# The slot belongs to the search while it reads (between waves too) and expires by itself if the process dies
# without giving it back: every wave renews it. Same shape as the Guide's long tasks (Autonomia::Guide::Tarefas::Semaforo).
module ConversationAudience::Semaphore
  PER_ACCOUNT = 'conversation_audience:account:'.freeze
  RUNNING = 'conversation_audience:running'.freeze
  LOCK = 'conversation_audience:semaphore'.freeze
  TOTAL = 3
  VALIDITY = 6.minutes

  module_function

  # -> true when the search has (or renewed) the slot.
  def enter(search)
    entered = false
    Redis::LockManager.new.with_lock(LOCK, 2) { entered = reserve(search.id.to_s, search.account_id) }
    entered
  end

  def leave(search)
    Redis::Alfred.with { |redis| redis.zrem(RUNNING, search.id.to_s) }
    Redis::Alfred.delete_if_equals("#{PER_ACCOUNT}#{search.account_id}", search.id.to_s)
  end

  def reserve(id, account_id)
    now = Time.current.to_f
    Redis::Alfred.zremrangebyscore(RUNNING, '-inf', now)
    owner = Redis::Alfred.get("#{PER_ACCOUNT}#{account_id}")
    return false if owner.present? && owner != id
    return false if Redis::Alfred.zscore(RUNNING, id).nil? && Redis::Alfred.zcard(RUNNING) >= TOTAL

    Redis::Alfred.set("#{PER_ACCOUNT}#{account_id}", id, ex: VALIDITY.to_i)
    Redis::Alfred.zadd(RUNNING, now + VALIDITY.to_i, id)
    true
  end
end
