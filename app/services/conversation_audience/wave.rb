# One wave of a reading search (#2277): the next pending batches (up to Reader::PARALLEL), read at once. Before
# paying, it checks the ceiling: if this wave could go past it, nothing is read and the search asks first.
#
# What each batch found is written as soon as the wave ends, so the list on the screen fills up wave by wave and a
# search stopped midway keeps who it found. A batch that failed stays pending and is read again after a pause
# (RETRY). What happens after MAX_ATTEMPTS depends on what failed:
# - the key (refused, no credit, no such model): the search stops as failed at once, every batch would fail too;
# - the AI was out (429, 5xx, timeout, network): the search stops as failed; "Tentar de novo" picks up from there;
# - the answer for those conversations (refused, empty or unreadable): the batch is skipped and the search goes on,
#   so one bad batch never blocks the rest. The screen says how many conversations were left unread.
class ConversationAudience::Wave
  CONTINUE = :continue
  RETRY = :retry
  DONE = :done
  CEILING = :ceiling
  FAILED = :failed
  MAX_ATTEMPTS = 3
  KEY_STATUSES = [401, 402, 403, 404].freeze

  def initialize(search, credential:)
    @search = search
    @account = search.account
    @credential = credential
  end

  def run
    batches = @search.batches.pending.order(:number).limit(ConversationAudience::Reader::PARALLEL).to_a
    return DONE if batches.empty?
    return CEILING if over_ceiling?(batches)

    results = ConversationAudience::Reader.new(@search, credential: @credential).call(with_texts(batches))
    results.each { |result| save(result) }
    outcome(results.select(&:error))
  end

  private

  def over_ceiling?(batches)
    expected = ConversationAudience::Cost.estimate_usd(batches.sum(&:chars), batches.size)
    @search.ceiling_usd.present? && @search.spent_usd + expected > @search.ceiling_usd
  end

  # Access is checked again on every wave: a conversation the person can no longer open is not read.
  def with_texts(batches)
    ids = ConversationAudience::Conversations.scope(@account, @search.user, nil).where(id: batches.flat_map(&:conversation_ids)).pluck(:id)
    texts = ConversationAudience::Transcript.new(@account).for(ids)
    batches.map { |batch| [batch, texts.slice(*batch.conversation_ids)] }
  end

  def save(result)
    cost = ConversationAudience::Cost.of(ConversationAudience::Reader::MODEL, result.usage)
    record_usage(result.usage) if result.usage.present?
    ConversationAudienceSearch.transaction do
      read = result.error ? retry_later(result, cost) : done(result, cost)
      # Added in the database, never from the value read before the wave: the ceiling counts every call.
      ConversationAudienceSearch.where(id: @search.id).update_all( # rubocop:disable Rails/SkipsModelValidations
        ['spent_usd = spent_usd + ?, conversations_read = conversations_read + ?, heartbeat_at = ?', cost, read, Time.current]
      )
    end
  end

  def retry_later(result, cost)
    batch = result.batch
    attempts = batch.attempts + 1
    skip = attempts >= MAX_ATTEMPTS && about_batch?(result.error)
    batch.update!(attempts: attempts, error: result.error.class.name, spent_usd: batch.spent_usd + cost,
                  status: skip ? ConversationAudienceBatch::SKIPPED : ConversationAudienceBatch::PENDING)
    0
  end

  def done(result, cost)
    add_people(result.people)
    result.batch.update!(status: ConversationAudienceBatch::DONE, error: nil, spent_usd: result.batch.spent_usd + cost)
    result.batch.conversation_ids.size
  end

  def outcome(failed)
    failed = failed.reject { |result| result.batch.status == ConversationAudienceBatch::SKIPPED }
    return CONTINUE if failed.empty?
    return FAILED if failed.any? { |result| key?(result.error) || (passing?(result.error) && result.batch.attempts >= MAX_ATTEMPTS) }

    RETRY
  end

  def key?(error)
    error.is_a?(Crm::Ai::ResponsesClient::Error) && KEY_STATUSES.include?(error.status.to_i)
  end

  # The client wraps network failures as passing errors of its own (rede: true).
  def passing?(error)
    error.is_a?(Crm::Ai::ResponsesClient::Error) && error.passageira?
  end

  # Neither the key nor the AI being out: the answer for these conversations (a 400, an empty or unreadable answer).
  def about_batch?(error)
    !key?(error) && !passing?(error)
  end

  # A contact with several conversations keeps the strongest group, and the reason of that conversation.
  def add_people(found)
    return if found.empty?

    owners = @account.conversations.where(id: found.pluck(:conversation_id)).pluck(:id, :contact_id).to_h
    contacts = @account.contacts.where(id: owners.values).index_by(&:id)
    found.each do |item|
      contact = contacts[owners[item[:conversation_id]]]
      add_person(contact, item) if contact
    end
  end

  def add_person(contact, item)
    person = @search.people.find_or_initialize_by(contact_id: contact.id)
    return if person.persisted? && !ConversationAudiencePerson.stronger?(item[:group], person.group)

    person.update!(conversation_id: item[:conversation_id], group: item[:group], reason: item[:reason], proofs: item[:proofs],
                   **reach(contact))
  end

  # Written once, when found: the screen polls the list and never normalizes phones again.
  def reach(contact)
    { contact_masked: ConversationAudience::Reach.masked(contact), left_aside: ConversationAudience::Reach.reason_for(contact) }
  end

  def record_usage(usage)
    Crm::Ai::UsageRecorder.record(account: @account, feature: ConversationAudience::Reader::FEATURE,
                                  model: ConversationAudience::Reader::MODEL, usage: usage,
                                  reasoning_effort: ConversationAudience::Reader::EFFORT)
  end
end
