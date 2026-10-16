# Mensagem rica nativa no plano B do WhatsApp Híbrido (chat#1709, fase 1), atrás da flag por conta
# `whatsapp_rich_native`. Sem a flag, nada muda: o formato sai como texto pelo WhatsApp API, como no #1555.
#
# Com a flag, quando a mensagem sai pelo WhatsApp API (rota direta ou plano B do 131047):
# - options vira lista, location vira localização e contact vira cartão de contato (Waha::RichPayload);
# - a mensagem ganha `rich_message_sent_as: 'native'` em vez de 'text' (a bolha mostra o formato, como na Cloud);
# - o id físico fica no source_id e no Redis, como no texto, para o ack e o eco acharem a mensagem.
# O resto (link_button, location_request, flow, link_preview) e a lista que não cabe nos limites seguem como texto.
#
# Peças, todas por prepend (config/initializers/whatsapp_rich_native.rb):
# - WhatsappHybrid::RichNative::Transport     em WhatsappHybrid::WebTransport (o envio);
# - WhatsappHybrid::RichNative::DeliveryMode  em RichMessages (o que o agente consulta, e a marca de texto);
# - WhatsappHybrid::RichNative::ReplyLink     em Whatsapp::IncomingMessageBaseService (liga a resposta à lista).
module WhatsappHybrid::RichNative
  FLAG = 'whatsapp_rich_native'.freeze
  SENT_AS = 'native'.freeze
  SUPPORTED_TYPES = Waha::RichPayload::KINDS

  module_function

  def enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O envio nativo desta mensagem, ou nil quando ela sai como sempre (sem flag, sem `rich_message`, tipo sem envio
  # nativo, ou entrada que não cabe na lista).
  def payload_for(message)
    return unless RichMessages.rich?(message) && enabled?(message.account)

    rich = message.content_attributes[RichMessages::KEY]
    Waha::RichPayload.build(rich, body: RichMessages.body_text(message), locale: message.account.locale)
  end

  # Grava, depois que o motor aceitou, a marca do formato e, quando o motor deu outro id à mensagem (a lista não leva
  # id gerado antes), o id físico no source_id e no Redis. NUNCA levanta: a mensagem já saiu, e um erro aqui viraria
  # falha do envio (e reenvio). Sem a marca, o envio marca "saiu como texto", que é o que acontecia antes.
  def mark_sent!(message, connection, physical_id)
    message.with_lock do
      columns = physical_id.present? && physical_id != message.source_id ? { source_id: physical_id } : {}
      message.update!(columns.merge(content_attributes: message.content_attributes.to_h.merge(RichMessages::SENT_AS_KEY => SENT_AS)))
    end
    remember_physical_id(message, connection, physical_id)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] rich native mark message=#{message.id} #{e.class}")
    nil
  end

  def remember_physical_id(message, connection, physical_id)
    return if physical_id.blank?

    ::Redis::Alfred.setex(WhatsappHybrid::WebTransport.message_key(connection, physical_id), message.id,
                          WhatsappHybrid::WebTransport::MESSAGE_KEY_TTL)
  end

  def sent_native?(message)
    message.content_attributes.to_h[RichMessages::SENT_AS_KEY] == SENT_AS
  end

  # A caixa responderia `:native` para este tipo: flag ligada, caixa híbrida e WhatsApp API pronto para esta conversa
  # (janela oficial fechada, conexão pronta, contato liberado pelo limite de conversas novas).
  def native_for?(inbox, type, conversation)
    SUPPORTED_TYPES.include?(type) && enabled?(inbox.account) && hybrid?(inbox) &&
      WhatsappHybrid::Router.new(conversation).web_reply_available?
  end

  # Os tipos que saem nativos nesta conversa agora (campo `whatsapp_api_rich_native` da conversa, para a tela do "+"):
  # com a flag, numa conversa cuja próxima resposta sai pelo WhatsApp API (`whatsapp_api_reply?`: janela oficial
  # fechada, plano B pronto, sem pausa). Senão, nenhum. A flag vem primeiro: conta sem ela não paga consulta nenhuma.
  # Fase 2 (caixa WAHA comum): acrescentar aqui o caso da caixa WAHA, com a mesma flag e os mesmos tipos.
  def types_for(conversation)
    return [] unless enabled?(conversation.account)
    return [] unless conversation.respond_to?(:whatsapp_api_reply?) && conversation.whatsapp_api_reply?

    SUPPORTED_TYPES.dup
  end

  def hybrid?(inbox)
    RichMessages.whatsapp_cloud?(inbox) && WhatsappHybrid::Config.account_allowed?(inbox.account_id) &&
      WhatsappHybrid::Config.hybrid_inbox?(inbox.id)
  end
end
