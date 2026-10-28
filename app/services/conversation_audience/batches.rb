# Splits the conversations of a search's period in reader batches (#2277): up to MAX_CONVERSATIONS conversations or
# MAX_CHARS characters each, the sizes the eval measured (smaller batches did not read better). Built once the plan
# is ready, so the plan shows the real count, time and cost; rebuilt if the person answers the question again.
module ConversationAudience::Batches
  MAX_CONVERSATIONS = 20
  MAX_CHARS = 60_000

  module_function

  # -> { conversations:, chars:, batches: }
  def build!(search)
    sizes = ConversationAudience::Conversations.sizes(search.account, search.user, search.since)
    groups = split(sizes)
    now = Time.current
    ConversationAudienceBatch.transaction do
      ConversationAudienceBatch.where(search_id: search.id).delete_all
      if groups.any?
        # Rows built here from the database's own ids; one insert for hundreds of batches.
        ConversationAudienceBatch.insert_all!(groups.each_with_index.map do |(ids, chars), index| # rubocop:disable Rails/SkipsModelValidations
          { search_id: search.id, number: index + 1, conversation_ids: ids, chars: chars, status: ConversationAudienceBatch::PENDING,
            created_at: now, updated_at: now }
        end)
      end
    end
    { conversations: sizes.size, chars: sizes.values.sum, batches: groups.size }
  end

  # [[ids, chars], ...]
  def split(sizes)
    sizes.each_with_object([]) do |(id, chars), groups|
      last = groups.last
      if last.nil? || last[0].size >= MAX_CONVERSATIONS || last[1] + chars > MAX_CHARS
        groups << [[id], chars]
      else
        last[0] << id
        last[1] += chars
      end
    end
  end
end
