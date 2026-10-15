# Prepend em Whatsapp::IncomingMessageBaseService (chat#1489). A bolha "não suportada" do Chatwoot passa a guardar
# o que a Meta disse dela e, quando a caixa pode, nasce pronta para ser recuperada pelo aparelho conectado:
# - `unsupported_type` (o `unsupported.type` da Meta: hsm, edit, poll_creation…) e `unsupported_error_code`
#   (131051, 131060…), em todas as caixas WhatsApp, para sabermos o que chega;
# - o tipo `unknown` vira a mesma bolha: hoje, com `errors`, a mensagem só ia ao log e a conversa nascia sem ela;
# - na caixa com WhatsApp API pronto e a flag `whatsapp_hybrid_recovery` ligada: `whatsapp_web_id` e
#   `hybrid_recovery: pending`, e o WhatsappHybrid::RecoverUnsupportedJob começa a perguntar ao motor.
# As chaves entram na montagem de `content_attributes` (como RichMessages::SelectedOption), antes do INSERT: o
# `message_created` já sai com elas, e a nossa IA sabe que não deve responder ao aviso.
module WhatsappHybrid::UnsupportedMessageExtension
  UNKNOWN_TYPE = 'unknown'.freeze

  private

  def create_messages
    return create_unsupported_message(messages_data.first) if message_type == UNKNOWN_TYPE

    super
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

  def unsupported_details(message)
    details = { 'unsupported_type' => message.dig(:unsupported, :type),
                'unsupported_error_code' => Array(message[:errors]).first&.dig(:code) }.compact
    return details if outgoing_echo

    details.merge(WhatsappHybrid::UnsupportedRecovery.initial_attributes(inbox, message[:id]))
  end
end
