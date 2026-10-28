# The text the readers get for each conversation (#2277), in the same shape the quality eval used:
#
#   === CONVERSA 4812 | criada 2026-06-25T14:32
#   [06-25T14:32] CLIENTE: Oi! Quanto fica para 2 pessoas?
#   [06-25T14:40] ASSISTENTE: ...
#
# Who spoke comes from Crm::Ai::PapelDaMensagem (the same roles every CRM AI reads): the customer, a person of the
# team (EQUIPE) or the company's automation (ASSISTENTE: our agent, follow-ups, integrations). Private notes and
# activity lines stay out. Attachments come as the text the platform already read (transcribed audio, image
# caption). A conversation longer than one reader call keeps its most recent messages.
class ConversationAudience::Transcript
  MESSAGE_TYPES = %w[incoming outgoing template].freeze
  MAX_CHARS = 60_000
  # More than fits in MAX_CHARS at the shortest line; a conversation is never loaded whole.
  MAX_MESSAGES = 2500
  LABELS = { 'customer' => 'CLIENTE', 'human_agent' => 'EQUIPE' }.freeze
  AUTOMATION = 'ASSISTENTE'.freeze

  def initialize(account)
    @account = account
    @timezone = Crm::Ai::Config.resolved_timezone(account: account)
    @robots = Crm::Ai::PapelDaMensagem.robos_da_conta(account.id)
  end

  # { conversation_id => text }, in the order of the ids; a conversation without messages is left out.
  def for(conversation_ids)
    created = @account.conversations.where(id: conversation_ids).pluck(:id, :created_at).to_h
    conversation_ids.each_with_object({}) do |id, texts|
      messages = latest(id)
      texts[id] = text(id, created[id], messages) if messages.any?
    end
  end

  private

  def latest(conversation_id)
    Message.where(account_id: @account.id, conversation_id: conversation_id, private: false, message_type: MESSAGE_TYPES)
           .includes(:attachments).reorder(created_at: :desc, id: :desc).limit(MAX_MESSAGES).to_a.reverse
  end

  def text(id, created_at, messages)
    header = "=== CONVERSA #{id} | criada #{stamp(created_at, '%Y-%m-%dT%H:%M')}\n"
    lines = messages.map { |message| line(message) }
    kept = []
    size = header.size
    lines.reverse_each do |line|
      break if size + line.size > MAX_CHARS

      kept.unshift(line)
      size += line.size
    end
    header + kept.join
  end

  def line(message)
    "[#{stamp(message.created_at, '%m-%dT%H:%M')}] #{label(message)}: #{content(message)}\n"
  end

  def label(message)
    LABELS.fetch(Crm::Ai::PapelDaMensagem.de(message, robos: @robots), AUTOMATION)
  end

  def content(message)
    parts = [message.content.to_s.strip]
    message.attachments.each { |attachment| parts << Crm::Ai::TextoDaMidia.fragmento(attachment) }
    parts.compact_blank.join(' ').squish.presence || '[mensagem sem texto]'
  end

  def stamp(time, format)
    time&.in_time_zone(@timezone)&.strftime(format).to_s
  end
end
