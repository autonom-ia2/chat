# Prepend em Whatsapp::SendOnWhatsappService (chat#1067). Só muda o caso que hoje termina em falha:
# texto livre fora da janela de 24h numa caixa com WhatsApp Híbrido. Template, pedido de contato,
# broadcast e tudo dentro da janela seguem exatamente o caminho original.
module WhatsappHybrid::SendOnWhatsappExtension
  private

  def perform_reply
    return super unless hybrid_web_candidate?

    router = WhatsappHybrid::Router.new(message.conversation)
    return super if router.cloud_window_open?
    # Conversation#can_reply? fica verdadeiro com o híbrido pronto; se esta mensagem não pode ir pelo
    # Web (origem desligada, por exemplo), ela falha como antes em vez de tentar a Cloud fora da janela.
    return fail_outside_window! unless router.route_for(message) == :web

    WhatsappHybrid::WebTransport.new(message: message, connection: router.connection, origin: router.origin_of(message)).perform
  end

  def hybrid_web_candidate?
    template_params.blank? && !contact_info_request? && !broadcast_destination? &&
      WhatsappHybrid::Config.account_allowed?(message.account_id) &&
      WhatsappHybrid::Connection.exists?(inbox_id: message.inbox_id)
  end

  def fail_outside_window!
    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  end
end
