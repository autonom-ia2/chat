# The conversation beside the list (#2277): the messages around the ones the reader gave as proof, marked as the
# reason, so the person checks why someone came in without leaving the screen. The reader's proofs are the
# transcript's [MM-DDTHH:MM] stamps, in the account's time zone; a message counts when its stamp is one of them.
# Only a conversation the person can still open (ConversationAudience::Conversations.scope) shows its messages.
class ConversationAudience::Peek
  AROUND = 2
  WITHOUT_PROOF = 30
  MAX = 80

  def initialize(person, user:)
    @person = person
    @user = user
    @account = person.search.account
    @timezone = Crm::Ai::Config.resolved_timezone(account: @account)
  end

  def messages
    return [] unless visible?

    all = Message.where(account_id: @account.id, conversation_id: @person.conversation_id, private: false,
                        message_type: ConversationAudience::Transcript::MESSAGE_TYPES)
                 .includes(:attachments).order(:created_at, :id).last(1000)
    counted = all.each_index.select { |index| proofs.include?(stamp(all[index])) }
    window(all, counted).map { |message| item(message, proofs.include?(stamp(message))) }
  end

  private

  def visible?
    ConversationAudience::Conversations.scope(@account, @user, nil).exists?(id: @person.conversation_id)
  end

  def proofs
    @proofs ||= Array(@person.proofs).to_set { |proof| proof.to_s.delete('[]').strip }
  end

  def window(all, counted)
    return all.last(WITHOUT_PROOF) if counted.empty?

    first = [counted.first - AROUND, 0].max
    all[first..(counted.last + AROUND)].last(MAX)
  end

  def item(message, counts)
    { from: message.incoming? ? 'contato' : 'equipe', date: message.created_at.in_time_zone(@timezone).strftime('%d/%m'),
      text: text(message), counts: counts }
  end

  def text(message)
    parts = [message.content.to_s.strip]
    message.attachments.each { |attachment| parts << Crm::Ai::TextoDaMidia.fragmento(attachment) }
    parts.compact_blank.join(' ').presence || '…'
  end

  def stamp(message)
    message.created_at.in_time_zone(@timezone).strftime('%m-%dT%H:%M')
  end
end
