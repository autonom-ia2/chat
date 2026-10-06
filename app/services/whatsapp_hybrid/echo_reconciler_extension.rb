# Prepend em Whatsapp::IncomingMessageBaseService (chat#1067). Quando a mensagem sai pelo WhatsApp API,
# a Meta devolve um eco (smb_message_echoes) para a Cloud. O wamid desse eco carrega o mesmo id físico
# que o WAHA usou; com isso a bolha que já existe ganha o wamid, em vez de nascer uma segunda.
# Sem id físico conhecido, segue o fluxo original (eco do celular, por exemplo).
module WhatsappHybrid::EchoReconcilerExtension
  private

  def process_messages
    return super unless outgoing_echo && WhatsappHybrid::Config.account_allowed?(inbox.account_id)

    target = hybrid_echo_target
    return super if target.nil?

    reconcile_hybrid_echo(target)
  end

  def hybrid_echo_target
    physical_id = WhatsappHybrid::Wamid.message_id(messages_data.first[:id].to_s)
    return if physical_id.blank?

    Message.find_by(inbox_id: inbox.id, source_id: physical_id, message_type: :outgoing)
  end

  def reconcile_hybrid_echo(message)
    attrs = message.content_attributes.to_h.merge('whatsapp_web_id' => message.source_id)
    changes = { source_id: messages_data.first[:id].to_s }
    # Envio que ficou sem confirmação do WAHA, mas a Meta comprovou que saiu.
    if message.failed?
      attrs.delete('external_error')
      changes[:status] = :sent
    end
    message.update!(changes.merge(content_attributes: attrs))
    Rails.logger.info("[whatsapp_hybrid] echo reconciled message=#{message.id} inbox=#{inbox.id}")
  end
end
