# Decide se uma mensagem da caixa Cloud sai pelo WhatsApp Web (WAHA) — chat#1067.
# A Cloud é sempre a primeira escolha. O Web só entra quando a janela oficial de 24h está fechada
# e tudo abaixo é verdade. Template, pedido de contato e recursos Meta nunca passam por aqui.
class WhatsappHybrid::Router
  CRM_FOLLOW_UP_ORIGIN = 'crm_follow_up'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  # Conversa pode receber texto livre pelo Web (usado para destravar o editor e pelo envio).
  def web_reply_available?
    web_ready? && !cloud_window_open?
  end

  def route_for(message)
    return :cloud if cloud_window_open?
    return :cloud unless web_ready? && web_allowed_for?(message) && reach_out.allowed?

    :web
  end

  # O WhatsApp API serviria, mas o limite de conversas novas do WhatsApp barrou este contato (chat#1486).
  def reach_out_refused?(message)
    web_ready? && web_allowed_for?(message) && !reach_out.allowed?
  end

  def reach_out
    @reach_out ||= WhatsappHybrid::ReachOut.new(connection, @conversation.contact)
  end

  # Conexão pronta e contato com telefone, independente da janela (o plano B usa isto).
  def web_ready?
    connection.present? && WhatsappHybrid::Config.routing_enabled? && connection.routable? && contact_phone.present?
  end

  # Botões, listas, carrossel, formulário e pesquisa são recursos Meta: pelo WhatsApp Web viram
  # texto solto (e chamam atenção de bloqueio). Só texto e anexos passam pelo Web.
  def web_allowed_for?(message)
    message.content_type == 'text' && connection.origin_enabled?(origin_of(message))
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
    # Lido como hash Ruby: o campo é JSON dupla-codificado e `->>` em SQL sempre devolve NULL.
    return CRM_FOLLOW_UP_ORIGIN if message.content_attributes.to_h['crm_follow_up_id'].present?
    return 'human' if message.sender_type == 'User'
    return 'bot' if message.sender_type.present?

    'automation'
  end
end
