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

  def session_name_for(inbox)
    "hybrid-#{inbox.channel.phone_number.to_s.delete('^0-9')}"
  end
end
