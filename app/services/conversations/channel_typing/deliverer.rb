# chat#1442 — "Digitando" no canal da conversa: WhatsApp Cloud oficial, Instagram e caixa WhatsApp API
# (Channel::Api provisionada para WAHA). Atende o robô externo (toggle_typing_status com deliver_to_channel)
# e o agente nativo (Autonomia::Agents::Operate::TypingIndicator delega para cá o WhatsApp oficial e o
# Instagram; a caixa WhatsApp API do agente nativo segue pelo evento do painel).
# Caixa oficial com WhatsApp Híbrido (chat#1067) segue pela Meta, como qualquer caixa oficial.
# Chave de instalação AI_HUMANIZE_CHANNEL_TYPING (ligada quando ausente): desligada, ninguém mostra
# "digitando" no canal.
# timeout (segundos) limita a chamada ao canal; o job informa, o agente nativo não (segue como era).
# É cosmético: nunca levanta. Falha vira log sem token e sem conteúdo: na Meta e no Instagram, a classe do
# erro ou o status HTTP da recusa; no WAHA, só a classe do erro (a mensagem dele traz URL e corpo).
class Conversations::ChannelTyping::Deliverer
  SENDER_ACTIONS = { 'on' => 'typing_on', 'off' => 'typing_off' }.freeze
  JID_SEPARATOR = '@'.freeze

  def self.supports?(conversation)
    return false unless Autonomia::Agents::Config.channel_typing_enabled?

    channel = conversation.inbox.channel
    case channel
    when Channel::Instagram then true
    when Channel::Whatsapp then channel.provider == 'whatsapp_cloud'
    when Channel::Api then channel.waha_provider? && Waha::Config.enabled?
    else false
    end
  end

  def initialize(conversation:, typing_status:, timeout: nil)
    @conversation = conversation
    @typing_status = typing_status
    @timeout = timeout
  end

  def perform
    return unless self.class.supports?(@conversation)

    response = deliver
    return unless response
    return if response.success?

    Rails.logger.warn("[channel_typing] refused conversation=#{@conversation.id} status=#{response.code}")
  rescue StandardError => e
    Rails.logger.warn("[channel_typing] failed conversation=#{@conversation.id} #{e.class}")
  end

  private

  def channel
    @conversation.inbox.channel
  end

  # Devolve a resposta HTTP do canal, ou nil quando não há o que conferir.
  def deliver
    case channel
    when Channel::Instagram then instagram_typing
    when Channel::Whatsapp then whatsapp_typing
    when Channel::Api then waha_typing
    end
  end

  # A Meta não tem "off": o indicador some sozinho (~25 s) ou quando a resposta chega.
  # A chamada também marca como lida a última mensagem recebida do cliente.
  def whatsapp_typing
    return unless @typing_status == 'on'

    # reorder: Message tem default_scope por created_at asc; com order, a mais antiga venceria.
    wamid, recebida_em = @conversation.messages.incoming.where.not(source_id: [nil, ''])
                                      .reorder(created_at: :desc).pick(:source_id, :created_at)
    # #2246: esta lida é do robô, não de uma pessoa no celular. Cobre a mensagem marcada e as anteriores.
    ConversaCanal::LeituraDoSistema.registrar(@conversation, ate: recebida_em) if wamid.present?
    channel.provider_service.send_typing_indicator(wamid, timeout: @timeout)
  end

  def instagram_typing
    action = SENDER_ACTIONS[@typing_status]
    message = @conversation.messages.last
    return unless action && message

    Instagram::SendOnInstagramService.new(message: message)
                                     .send_sender_action(@conversation.contact_inbox&.source_id, action, timeout: @timeout)
  end

  # Só conversa 1:1 com chat id do WhatsApp conhecido: grupo, lista e canal não mostram "digitando", e
  # contato que ainda não tem chat id (o ContactInbox guarda só um UUID) fica sem.
  # Devolve nil de propósito: o Waha::Client devolve um Hash, e o perform chamaria success? nele.
  def waha_typing
    session = channel.additional_attributes.to_h['session']
    chat_id = Waha::ContactChatId.primary(@conversation.contact, contact_inbox: @conversation.contact_inbox).to_s
    return if session.blank? || chat_id.exclude?(JID_SEPARATOR)
    return if Crm::WhatsappGroupDetector.group_conversation?(@conversation)

    options = { session: session, chat_id: chat_id, **{ timeout: @timeout }.compact }
    case @typing_status
    when 'on' then Waha::Client.new.start_typing(**options)
    when 'off' then Waha::Client.new.stop_typing(**options)
    end
    nil
  end
end
