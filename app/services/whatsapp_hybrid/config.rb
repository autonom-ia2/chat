# Disponibilidade do WhatsApp Híbrido (chat#1067). Tudo por ENV, para ligar/desligar sem deploy de código.
#   WHATSAPP_HYBRID_ACCOUNT_IDS     — contas que veem a aba (ex.: "1,16"); "*" libera todas. Vazio = ninguém.
#   WHATSAPP_HYBRID_ROUTING_ENABLED — kill switch global do roteador ("false" volta tudo para a Cloud).
module WhatsappHybrid::Config
  module_function

  def available_for?(inbox)
    return false unless Waha::Config.enabled?
    return false unless inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'whatsapp_cloud'

    account_allowed?(inbox.account_id)
  end

  def routing_enabled?
    ENV.fetch('WHATSAPP_HYBRID_ROUTING_ENABLED', 'true') != 'false'
  end

  def account_allowed?(account_id)
    ids = ENV.fetch('WHATSAPP_HYBRID_ACCOUNT_IDS', '').split(',').map(&:strip)
    ids.include?('*') || ids.include?(account_id.to_s)
  end

  INBOX_FLAG_TTL = 60

  # A caixa tem conexão híbrida? Responde do Redis (60 s) para a lista de conversas não consultar o banco
  # a cada conversa de WhatsApp. A conexão apaga a marca ao ser criada ou removida.
  def hybrid_inbox?(inbox_id)
    cached = ::Redis::Alfred.get(inbox_flag_key(inbox_id))
    return cached == '1' unless cached.nil?

    present = WhatsappHybrid::Connection.exists?(inbox_id: inbox_id)
    ::Redis::Alfred.setex(inbox_flag_key(inbox_id), present ? '1' : '0', INBOX_FLAG_TTL)
    present
  end

  def forget_inbox(inbox_id)
    ::Redis::Alfred.delete(inbox_flag_key(inbox_id))
  end

  def inbox_flag_key(inbox_id)
    "whatsapp_hybrid:inbox:#{inbox_id}"
  end

  def session_name_for(inbox)
    "hybrid-#{inbox.channel.phone_number.to_s.delete('^0-9')}"
  end
end
