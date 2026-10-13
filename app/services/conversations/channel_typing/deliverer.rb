# chat#1442 — "Digitando" no canal da conversa: WhatsApp Cloud oficial e Instagram. Os outros canais não
# entram (WAHA/híbrido é a entrega 2). Atende o robô externo (toggle_typing_status com deliver_to_channel)
# e o agente nativo (Autonomia::Agents::Operate::TypingIndicator delega para cá).
# Chave de instalação AI_HUMANIZE_CHANNEL_TYPING (ligada quando ausente): desligada, ninguém mostra
# "digitando" no canal.
# É cosmético: nunca levanta. Recusa do canal vira log com o status HTTP, sem token e sem conteúdo.
class Conversations::ChannelTyping::Deliverer
  SENDER_ACTIONS = { 'on' => 'typing_on', 'off' => 'typing_off' }.freeze

  def self.supports?(conversation)
    return false unless Autonomia::Agents::Config.channel_typing_enabled?

    channel = conversation.inbox.channel
    channel.is_a?(Channel::Instagram) || (channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud')
  end

  def initialize(conversation:, typing_status:)
    @conversation = conversation
    @typing_status = typing_status
  end

  def perform
    return unless self.class.supports?(@conversation)

    response = channel.is_a?(Channel::Instagram) ? instagram_typing : whatsapp_typing
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

  # A Meta não tem "off": o indicador some sozinho (~25 s) ou quando a resposta chega.
  # A chamada também marca como lida a última mensagem recebida do cliente.
  def whatsapp_typing
    return unless @typing_status == 'on'

    # reorder: Message tem default_scope por created_at asc; com order, a mais antiga venceria.
    wamid = @conversation.messages.incoming.where.not(source_id: [nil, '']).reorder(created_at: :desc).pick(:source_id)
    channel.provider_service.send_typing_indicator(wamid)
  end

  def instagram_typing
    action = SENDER_ACTIONS[@typing_status]
    message = @conversation.messages.last
    return unless action && message

    Instagram::SendOnInstagramService.new(message: message).send_sender_action(@conversation.contact_inbox&.source_id, action)
  end
end
