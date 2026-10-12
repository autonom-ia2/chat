class Crm::FollowUps::MessagingWindow
  WHATSAPP_API_DEFAULT_WINDOW = 24.hours

  def initialize(conversation, at: nil)
    @conversation = conversation
    @at = at || Time.current
  end

  def whatsapp_capable?
    inbox = @conversation.inbox
    return false if inbox.blank?

    case inbox.channel_type
    when 'Channel::Whatsapp'
      true
    when 'Channel::TwilioSms'
      inbox.channel.medium == 'whatsapp'
    when 'Channel::Api'
      inbox.channel.whatsapp_api_campaign_channel?
    else
      false
    end
  end

  def can_send_session_message?
    return false unless whatsapp_capable?
    # WAHA/Evolution (WhatsApp não-oficial) NÃO tem a janela de 24h da Meta nem templates aprovados:
    # pode mandar mensagem livre a qualquer momento. Então a IA SEMPRE gera o texto (free_form) — vale
    # para o auto-followup E para o callback. Os canais oficiais seguem a regra da janela abaixo.
    return true if waha_unrestricted?

    window = effective_window
    return true if window.blank?

    last_incoming = @conversation.messages.incoming.last
    return false if last_incoming.blank?

    @at < last_incoming.created_at + window
  end

  # Fora das 24h numa caixa Oficial com WhatsApp Híbrido (chat#1067) pronto, o texto livre do CRM sai pelo
  # WhatsApp API (o roteador escolhe o transporte). Só vale para a origem crm_follow_up ligada na conexão.
  # Pesa o banco só depois de passar pelo que o Config já responde (conta no piloto, caixa com conexão).
  def hybrid_web_available?
    return false unless hybrid_configured?
    return false if can_send_session_message?

    router = WhatsappHybrid::Router.new(@conversation)
    router.web_ready? && router.connection.origin_enabled?(WhatsappHybrid::Router::CRM_FOLLOW_UP_ORIGIN)
  end

  # A caixa é Oficial (Cloud), a conta está no piloto e existe conexão do Híbrido (pronta ou não). Não olha a janela
  # nem o estado da conexão: serve para distinguir "Híbrido caiu" de "esta caixa nunca teve Híbrido".
  def hybrid_configured?
    inbox = @conversation.inbox
    return false unless inbox&.channel_type == 'Channel::Whatsapp'
    return false unless WhatsappHybrid::Config.account_allowed?(inbox.account_id)

    WhatsappHybrid::Config.hybrid_inbox?(inbox.id)
  end

  # WhatsApp não-oficial via WAHA (Channel::Api provider 'waha'): sem janela/template.
  def waha_unrestricted?
    channel = @conversation.inbox&.channel
    return false unless channel.is_a?(Channel::Api)

    (channel.respond_to?(:waha_provider?) && channel.waha_provider?) ||
      channel.additional_attributes.to_h['whatsapp_api_provider'] == 'waha'
  end

  def requires_template?
    whatsapp_capable? && !can_send_session_message?
  end

  def effective_window
    inbox = @conversation.inbox
    case inbox.channel_type
    when 'Channel::Whatsapp'
      Conversations::MessageWindowService::MESSAGING_WINDOW_24_HOURS
    when 'Channel::TwilioSms'
      inbox.channel.medium == 'whatsapp' ? Conversations::MessageWindowService::MESSAGING_WINDOW_24_HOURS : nil
    when 'Channel::Api'
      return nil unless inbox.channel.whatsapp_api_campaign_channel?

      hours = inbox.channel.additional_attributes.to_h['agent_reply_time_window'].presence
      hours ? hours.to_i.hours : WHATSAPP_API_DEFAULT_WINDOW
    end
  end
end
