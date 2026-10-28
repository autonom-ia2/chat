# Which conversations a search reads (#2277): the conversations the person who asked can open (the rule of the
# conversation list: inbox, team and pipeline access, roles that only read included, #1800), with activity in the
# chosen period, and their size, measured in the database so the plan can show cost and time before anything is read.
# An administrator reads the whole account; a role limited to some inboxes never gets people from the others.
module ConversationAudience::Conversations
  # Per message overhead in the transcript: "[MM-DDTHH:MM] CLIENTE: " and the line break.
  LINE_OVERHEAD = 25
  # Per attachment: the "[áudio transcrito]: " style label, plus the text the platform read (Crm::Ai::TextoDaMidia).
  ATTACHMENT_SIZE = "30 + COALESCE(LENGTH(attachments.meta->>'transcribed_text'), 0) + " \
                    "COALESCE(LENGTH(attachments.meta->>'ai_caption'), 0)".freeze

  module_function

  def scope(account, user, since)
    return account.conversations.none if user.nil?

    visible = Conversations::PermissionFilterService.new(account.conversations, user, account, for_reading: true).perform
    since ? visible.where('conversations.last_activity_at >= ?', since) : visible
  end

  # The ones of conversation_ids the person can still open: who was found before a lost access is neither shown nor saved.
  def visible_ids(account, user, conversation_ids)
    scope(account, user, nil).where(id: conversation_ids).pluck(:id).to_set
  end

  # { '7d' => 64, '30d' => 286, ... } so the screen never offers an empty period.
  def counts(account, user)
    ConversationAudienceSearch::PERIODS.transform_values { |window| scope(account, user, window&.ago).count }
  end

  # { conversation_id => chars } for the conversations of the period that have something to read, oldest first, each
  # capped at what one reader call takes (the transcript keeps the most recent messages).
  def sizes(account, user, since)
    ids = scope(account, user, since).reorder(:id).pluck(:id)
    ids.each_slice(1000).with_object({}) do |slice, sizes|
      texts = messages(account, slice).sum(Arel.sql("COALESCE(LENGTH(messages.content), 0) + #{LINE_OVERHEAD}"))
      media = messages(account, slice).joins(:attachments).sum(Arel.sql(ATTACHMENT_SIZE))
      texts.each { |id, chars| sizes[id] = [chars.to_i + media[id].to_i, ConversationAudience::Transcript::MAX_CHARS].min }
    end.sort.to_h
  end

  def messages(account, conversation_ids)
    Message.where(account_id: account.id, conversation_id: conversation_ids, private: false)
           .where(message_type: ConversationAudience::Transcript::MESSAGE_TYPES)
           .reorder(nil).group(:conversation_id)
  end
end
