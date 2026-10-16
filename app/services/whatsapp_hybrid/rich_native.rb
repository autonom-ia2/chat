# Mensagem rica nativa no plano B do WhatsApp Híbrido (chat#1709, fase 1), atrás da flag por conta
# `whatsapp_rich_native`. Flag, marca e referência da resposta são comuns ao motor: Waha::RichNative (a fase 2, caixa
# WAHA comum, usa as mesmas). Sem a flag, nada muda: o formato sai como texto pelo WhatsApp API, como no #1555.
#
# Com a flag, quando a mensagem sai pelo WhatsApp API (rota direta ou plano B do 131047):
# - options vira lista, location vira localização e contact vira cartão de contato (Waha::RichPayload);
# - a mensagem ganha `rich_message_sent_as: 'native'` em vez de 'text' (a bolha mostra o formato, como na Cloud);
# - o id físico fica no source_id e no Redis, como no texto, para o ack e o eco acharem a mensagem;
# - recusa explícita do motor (4xx, 501), em que nada saiu, manda UMA vez o texto de sempre.
# O resto (link_button, location_request, flow, link_preview) e o formato que não cabe nos limites seguem como texto.
#
# Peças por prepend (config/initializers/whatsapp_rich_native.rb):
# - WhatsappHybrid::RichNative::Transport     em WhatsappHybrid::WebTransport (o envio);
# - WhatsappHybrid::RichNative::DeliveryMode  em RichMessages (`delivery_mode` e a marca de texto);
# - WhatsappHybrid::RichNative::ReplyLink     em Whatsapp::IncomingMessageBaseService (liga a resposta à lista).
# E duas linhas no core, no mesmo padrão do `whatsapp_api_reply`: o jbuilder da conversa e o
# Conversations::EventDataPresenter expõem `whatsapp_api_rich_native` (Waha::RichNative.types_for).
module WhatsappHybrid::RichNative
  FLAG = Waha::RichNative::FLAG
  SENT_AS = Waha::RichNative::SENT_AS
  SUPPORTED_TYPES = Waha::RichNative::KINDS
  # Tipos que saem nativos sempre que a mensagem passa na validação do tipo (o tradutor não tem limite a mais). A
  # lista (`options`) depende do conteúdo: sem a mensagem, `delivery_mode` não promete `:native` para ela.
  CONTENT_FREE_TYPES = %w[location contact].freeze
  # Status do motor em que o pedido foi recusado e nada saiu: 4xx e 501 (formato não implementado no motor).
  NOT_IMPLEMENTED = 501
  CAPPED_ERROR = 'error 475'.freeze

  module_function

  def enabled?(account)
    Waha::RichNative.enabled?(account)
  end

  def sent_native?(message)
    Waha::RichNative.sent_native?(message)
  end

  # O envio nativo desta mensagem, ou nil quando ela sai como sempre (sem flag, sem `rich_message`, tipo sem envio
  # nativo, ou entrada que não cabe). O id da mensagem vai em cada `rowId` da lista (Waha::RichNative.row_id).
  def payload_for(message)
    return unless RichMessages.rich?(message) && enabled?(message.account)

    rich = message.content_attributes[RichMessages::KEY]
    Waha::RichPayload.build(rich, body: RichMessages.body_text(message), locale: message.account.locale, reference: message.id)
  end

  # O motor recusou o pedido e nada saiu: dá para mandar o texto sem duplicar. Sem resposta, resposta ilegível, 5xx
  # e as recusas do WhatsApp que o envio já trata (463, 475) ficam como estão.
  def nothing_sent?(error)
    return false if error.is_a?(Waha::Client::Timeout) || error.is_a?(Waha::Client::InvalidResponse)
    return false if WhatsappHybrid::ReachOut.engine_refusal?(error) || error.message.to_s.include?(CAPPED_ERROR)

    status = error.status.to_i
    status.between?(400, 499) || status == NOT_IMPLEMENTED
  end

  # Marca e source_id (Waha::RichNative.mark_sent!) e o id físico no Redis, para o ack. Nunca levanta.
  def mark_sent!(message, connection, physical_id)
    return unless Waha::RichNative.mark_sent!(message, physical_id)

    remember_physical_id(message, connection, physical_id)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] rich native id not remembered message=#{message.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    nil
  end

  def remember_physical_id(message, connection, physical_id)
    return if physical_id.blank?

    ::Redis::Alfred.setex(WhatsappHybrid::WebTransport.message_key(connection, physical_id), message.id,
                          WhatsappHybrid::WebTransport::MESSAGE_KEY_TTL)
  end

  # `delivery_mode` responde `:native` só quando o envio mandaria nativo: a MESMA regra do envio. O roteador decide
  # `route_for(message) == :web` (janela fechada, conexão pronta, origem ligada, contato liberado) e o tradutor monta
  # o pedido. Sem `message`, uma mensagem de rascunho do tipo (sem remetente: origem 'automation') responde pelo
  # roteador, e só os tipos que não dependem do conteúdo (CONTENT_FREE_TYPES) podem ser `:native`.
  def native_for?(inbox, type, conversation, message: nil)
    return false unless SUPPORTED_TYPES.include?(type) && enabled?(inbox.account) && hybrid?(inbox)

    draft = message || draft_message(inbox, type, conversation)
    return false unless WhatsappHybrid::Router.new(conversation).route_for(draft) == :web

    message ? payload_for(message).present? : CONTENT_FREE_TYPES.include?(type)
  end

  def draft_message(inbox, type, conversation)
    Message.new(account_id: inbox.account_id, inbox: inbox, conversation: conversation, message_type: :outgoing,
                content_type: :text, content_attributes: { RichMessages::KEY => { 'type' => type } })
  end

  # Esta conversa manda nativo pelo WhatsApp API agora (Waha::RichNative.types_for). Checagens sem consulta primeiro
  # (canal da caixa já carregada, contas do Híbrido no ENV, caixa híbrida no Redis, `api_reply` já calculado), e só
  # então a flag da conta: a lista de conversas não paga consulta por conversa comum.
  def native_route?(conversation, api_reply: nil)
    return false unless api_reply != false && hybrid_conversation?(conversation) && enabled?(conversation.account)

    api_reply.nil? ? conversation.whatsapp_api_reply? : api_reply
  end

  # Sem consulta ao banco: o canal da caixa já carregada, as contas do Híbrido no ENV e a caixa híbrida no Redis.
  def hybrid_conversation?(conversation)
    conversation.inbox&.channel_type == 'Channel::Whatsapp' && WhatsappHybrid::Config.account_allowed?(conversation.account_id) &&
      WhatsappHybrid::Config.hybrid_inbox?(conversation.inbox_id)
  end

  def hybrid?(inbox)
    RichMessages.whatsapp_cloud?(inbox) && WhatsappHybrid::Config.account_allowed?(inbox.account_id) &&
      WhatsappHybrid::Config.hybrid_inbox?(inbox.id)
  end
end
