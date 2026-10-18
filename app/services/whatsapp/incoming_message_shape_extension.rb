# Prepend em Whatsapp::IncomingMessageBaseService (chat#1816). O Chatwoot lê text, button, name, interactive (e, dentro
# dele, nfm_reply, button_reply e list_reply) e referral com dig/to_h, que levantam quando a Meta manda texto no lugar
# do objeto. Esses métodos recebem uma cópia da mensagem sem os campos fora do formato. Payload válido passa o próprio
# objeto, sem cópia: há extensão que reconhece a mensagem por identidade (WhatsappHybrid::UnsupportedMessageExtension).
module Whatsapp::IncomingMessageShapeExtension
  OBJECT_FIELDS = %i[text button name interactive referral].freeze
  INTERACTIVE_OBJECT_FIELDS = %i[nfm_reply button_reply list_reply].freeze

  def message_content(message)
    super(well_formed_message(message))
  end

  def referral_attributes(message)
    super(well_formed_message(message))
  end

  private

  def message_content_attributes(message)
    super(well_formed_message(message))
  end

  def well_formed_message(message)
    malformed = malformed_keys(message, OBJECT_FIELDS)
    interactive = message[:interactive]
    malformed_replies = interactive.is_a?(Hash) ? malformed_keys(interactive, INTERACTIVE_OBJECT_FIELDS) : []
    return message if malformed.empty? && malformed_replies.empty?

    shaped = message.except(*malformed)
    malformed_replies.empty? ? shaped : shaped.merge(interactive: interactive.except(*malformed_replies))
  end

  def malformed_keys(hash, keys)
    keys.select { |key| hash.key?(key) && !hash[key].is_a?(Hash) }
  end
end
