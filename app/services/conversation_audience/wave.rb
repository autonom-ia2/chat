# One wave of a reading search (#2277): the next pending batches (up to Reader::PARALLEL), read at once. Before
# paying, it checks the ceiling: if this wave could go past it, nothing is read and the search asks first.
#
# What each batch found is written as soon as the wave ends, so the list on the screen fills up wave by wave and a
# search stopped midway keeps who it found. A batch that failed stays pending and is read again in the next wave;
# after MAX_ATTEMPTS, or when the failure will not pass by itself (key revoked, quota), the search stops as failed.
class ConversationAudience::Wave
  CONTINUE = :continue
  DONE = :done
  CEILING = :ceiling
  FAILED = :failed
  MAX_ATTEMPTS = 3

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
    failed?(results) ? FAILED : CONTINUE
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
      result.error ? retry_later(result, cost) : done(result, cost)
      @search.update!(spent_usd: @search.spent_usd + cost, heartbeat_at: Time.current)
    end
  end

  def retry_later(result, cost)
    batch = result.batch
    batch.update!(attempts: batch.attempts + 1, error: result.error.class.name, spent_usd: batch.spent_usd + cost)
  end

  def done(result, cost)
    add_people(result.people)
    result.batch.update!(status: ConversationAudienceBatch::DONE, error: nil, spent_usd: result.batch.spent_usd + cost)
    @search.increment(:conversations_read, result.batch.conversation_ids.size)
  end

  def failed?(results)
    results.any? do |result|
      result.error && (result.batch.attempts >= MAX_ATTEMPTS || !passing?(result.error))
    end
  end

  # What can pass by itself: the AI's own passing failures (429, 5xx, timeout), an empty or unreadable answer, and
  # anything that is not an answer from the AI (network). A refused key or exhausted quota does not pass.
  def passing?(error)
    return true unless error.is_a?(Crm::Ai::ResponsesClient::Error)

    error.passageira? || error.message == 'empty_response'
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
