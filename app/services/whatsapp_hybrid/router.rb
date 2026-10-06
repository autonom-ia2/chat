# Decide se uma mensagem da caixa Cloud sai pelo WhatsApp Web (WAHA) — chat#1067.
# A Cloud é sempre a primeira escolha. O Web só entra quando a janela oficial de 24h está fechada
# e tudo abaixo é verdade. Template, pedido de contato e recursos Meta nunca passam por aqui.
class WhatsappHybrid::Router
  def initialize(conversation)
    @conversation = conversation
  end

  # Conversa pode receber texto livre pelo Web (usado para destravar o editor e pelo envio).
  def web_reply_available?
    connection.present? && WhatsappHybrid::Config.routing_enabled? && connection.routable? &&
      !cloud_window_open? && contact_phone.present?
  end

  def route_for(message)
    return :cloud if cloud_window_open?
    return :cloud unless web_reply_available?
    return :cloud unless connection.origin_enabled?(origin_of(message))

    :web
  end

  def cloud_window_open?
    Conversations::MessageWindowService.new(@conversation).can_reply?
  end

  def connection
    return @connection if defined?(@connection)

    @connection = WhatsappHybrid::Connection.find_by(inbox_id: @conversation.inbox_id)
  end

  # Só telefone de verdade: contato só com BSUID (identificador da Meta) não vai para o Web.
  def contact_phone
    @conversation.contact&.phone_number.to_s.delete('^0-9').presence
  end

  def origin_of(message)
    return 'campaign' if message.additional_attributes.to_h['campaign_id'].present?
    return 'human' if message.sender_type == 'User'
    return 'bot' if message.sender_type.present?

    'automation'
  end
end
