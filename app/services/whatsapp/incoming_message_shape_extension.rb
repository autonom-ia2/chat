# Prepend em Whatsapp::IncomingMessageBaseService (chat#1816). O Chatwoot lê text, button, name, interactive (e, dentro
# dele, nfm_reply, button_reply e list_reply) e referral com dig/to_h, que levantam quando a Meta manda texto no lugar
# do objeto. Esses métodos recebem uma cópia da mensagem sem os campos fora do formato; payload válido passa igual.
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
    shaped = message.except(*malformed_keys(message, OBJECT_FIELDS))
    interactive = shaped[:interactive]
    return shaped if interactive.nil?

    shaped.merge(interactive: interactive.except(*malformed_keys(interactive, INTERACTIVE_OBJECT_FIELDS)))
  end

  def malformed_keys(hash, keys)
    keys.select { |key| hash.key?(key) && !hash[key].is_a?(Hash) }
  end
end
