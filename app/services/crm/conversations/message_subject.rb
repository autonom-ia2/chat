# Assunto de uma mensagem (#1143): quem responde escolhe o assunto, e a mensagem guarda o card em
# content_attributes.crm_card_id. O valor vem de fora (navegador, API, bots), então é conferido antes de a mensagem
# ser gravada: só fica um id inteiro de um card desta conversa (o mesmo conjunto do ConversationCardFinder, na mesma
# conta). Qualquer outro valor sai, e nada além dessa chave é tocado.
class Crm::Conversations::MessageSubject
  KEY = 'crm_card_id'.freeze

  def initialize(message)
    @message = message
  end

  def sanitize
    attributes = @message.content_attributes.to_h.with_indifferent_access
    return unless attributes.key?(KEY)

    card_id = valid_card_id(attributes[KEY])
    @message.content_attributes = card_id ? attributes.merge(KEY => card_id) : attributes.except(KEY)
  end

  private

  def valid_card_id(value)
    card_id = integer_id(value)
    return if card_id.nil? || @message.conversation.blank?

    card_id if conversation_cards.exists?(id: card_id)
  end

  def integer_id(value)
    return value if value.is_a?(Integer)

    Integer(value, 10, exception: false) if value.is_a?(String)
  end

  def conversation_cards
    Crm::Cards::ConversationCardFinder.new(account: @message.conversation.account).all(@message.conversation)
  end
end
