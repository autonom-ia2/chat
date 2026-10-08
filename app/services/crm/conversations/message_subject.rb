# Assunto de uma mensagem (#1143): quem responde escolhe o assunto, e a mensagem guarda o card em
# content_attributes.crm_card_id. O valor vem do navegador, então só fica se for um card desta conversa
# (o mesmo conjunto do ConversationCardFinder, na mesma conta); qualquer outro id é retirado.
class Crm::Conversations::MessageSubject
  KEY = 'crm_card_id'.freeze

  def initialize(message)
    @message = message
  end

  def sanitize!
    card_id = @message.content_attributes.to_h.with_indifferent_access[KEY]
    return if card_id.blank?
    return if conversation_card_ids.include?(card_id.to_i)

    # Sem callbacks: retirar uma marca inválida não é uma edição da mensagem e não pode disparar message_updated.
    @message.update_columns(content_attributes: @message.content_attributes.to_h.except(KEY, KEY.to_sym)) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def conversation_card_ids
    Crm::Cards::ConversationCardFinder.new(account: @message.account).all(@message.conversation).pluck(:id)
  end
end
