# Prepend em Whatsapp::IncomingMessageBaseService (chat#1489). A bolha "não suportada" do Chatwoot passa a guardar
# o que a Meta disse dela e, quando a caixa pode, nasce pronta para ser recuperada pelo aparelho conectado:
# - `unsupported_type` (o `unsupported.type` da Meta: hsm, edit, poll_creation…) e `unsupported_error_code`
#   (131051, 131060…), em todas as caixas WhatsApp, para sabermos o que chega;
# - com a flag `whatsapp_hybrid_recovery` ligada na conta, a mensagem recebida do tipo `unknown` vira a mesma bolha
#   (hoje, com `errors`, ela só vai ao log). Flag desligada, ou eco de saída: exatamente o caminho de hoje;
# - na caixa com WhatsApp API pronto, com a flag e `unsupported.type` de mensagem nova: `whatsapp_web_id` e
#   `hybrid_recovery: pending`, e o WhatsappHybrid::RecoverUnsupportedJob começa a perguntar ao motor.
# As chaves entram na montagem de `content_attributes` (como RichMessages::SelectedOption), antes do INSERT: o
# `message_created` já sai com elas.
module WhatsappHybrid::UnsupportedMessageExtension
  UNKNOWN_TYPE = 'unknown'.freeze

  private

  def create_messages
    return create_unsupported_message(messages_data.first) if unknown_as_unsupported?

    super
  end

  def unknown_as_unsupported?
    message_type == UNKNOWN_TYPE && !outgoing_echo &&
      inbox.account.feature_enabled?(WhatsappHybrid::UnsupportedRecovery::FEATURE)
  end

  def create_unsupported_message(message)
    @unsupported_source = message
    super
    return unless WhatsappHybrid::UnsupportedRecovery.pending?(@message)

    WhatsappHybrid::RecoverUnsupportedJob.set(wait: WhatsappHybrid::UnsupportedRecovery::RETRY_DELAYS.first)
                                         .perform_later(@message.id)
  end

  def message_content_attributes(message)
    return super unless @unsupported_source && message.equal?(@unsupported_source)

    super.merge(unsupported_details(message))
  end

  # `unsupported` e `errors` fora do formato da Meta (texto no lugar do objeto) não derrubam o recebimento: sem tipo
  # nem código, como o ConversaCanal::TipoNaoSuportado.
  def unsupported_details(message)
    type = hash_value(message[:unsupported], :type)
    details = { 'unsupported_type' => type, 'unsupported_error_code' => hash_value(Array(message[:errors]).first, :code) }.compact
    return details if outgoing_echo

    details.merge(WhatsappHybrid::UnsupportedRecovery.initial_attributes(inbox, message[:id], type))
  end

  def hash_value(value, key)
    value[key] if value.is_a?(Hash)
  end
end
