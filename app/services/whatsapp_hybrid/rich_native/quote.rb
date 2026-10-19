# Prepend em WhatsappHybrid::WebTransport (chat#1709, fase 3): no plano B do Híbrido, a citação do painel ("Responder")
# vai junto no envio pelo motor. Antes, o `in_reply_to` só valia na Cloud: pelo plano B a mensagem saía sem citação.
# Com a flag `whatsapp_rich_native` e `in_reply_to`, todo `send_*` deste envio leva `reply_to` = o id físico da citada
# (WhatsappHybrid::RichNative::QuotingClient), sem editar o web_transport.rb. Sem id físico, sai sem citação, como antes.
# Id físico da citada: o que está dentro do wamid (mensagem que passou pela Cloud, Wamid.message_id) ou, nas que só
# passaram pelo motor, o `whatsapp_web_id` do eco ou o próprio `source_id`.
module WhatsappHybrid::RichNative::Quote
  def self.quoted_id(message)
    return unless Waha::RichNative.enabled?(message.account)

    target_id = message.content_attributes.to_h['in_reply_to']
    return if target_id.blank?

    quoted = Message.find_by(id: target_id, conversation_id: message.conversation_id)
    physical_id_of(quoted) if quoted
  end

  # O id físico de uma mensagem do Híbrido, ou nil (inclusive o provisório da lista, que não é id do WhatsApp).
  def self.physical_id_of(message)
    source = message.source_id.to_s
    return WhatsappHybrid::Wamid.message_id(source) if source.start_with?(WhatsappHybrid::Wamid::PREFIX)

    physical = message.content_attributes.to_h['whatsapp_web_id'].presence || source.presence
    physical unless physical.nil? || physical.start_with?(Waha::RichNative::PENDING_PREFIX)
  end

  private

  def deliver(chat_id, physical_id)
    quoted = WhatsappHybrid::RichNative::Quote.quoted_id(@message)
    return super if quoted.blank?

    original = @client
    @client = WhatsappHybrid::RichNative::QuotingClient.new(original, quoted)
    begin
      super
    ensure
      @client = original
    end
  end
end
