class Instagram::SendOnInstagramService < Instagram::BaseSendService
  # Indicador "digitando" do Instagram (sender_action typing_on/typing_off) para o id do contato.
  # Usado pela entrega humanizada do agente nativo (Autonomia). BEST-EFFORT: devolve nil em qualquer
  # erro/credencial ausente, sem levantar (typing é cosmético).
  def send_sender_action(recipient_id, action)
    return if recipient_id.blank? || channel.blank?

    instagram_id = channel.instagram_id.presence || 'me'
    HTTParty.post(
      "https://graph.instagram.com/v22.0/#{instagram_id}/messages",
      body: { recipient: { id: recipient_id }, sender_action: action },
      query: { access_token: channel.access_token }
    )
  rescue StandardError => e
    Rails.logger.warn("[instagram][typing] failed #{e.class}")
    nil
  end

  private

  def channel_class
    Channel::Instagram
  end

  # Deliver a message with the given payload.
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api
  def send_message(message_content)
    access_token = channel.access_token
    query = { access_token: access_token }
    instagram_id = channel.instagram_id.presence || 'me'

    response = HTTParty.post(
      "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}/#{instagram_id}/messages",
      body: message_content,
      query: query
    )

    process_response(response, message_content)
  end

  def merge_human_agent_tag(params)
    global_config = GlobalConfig.get('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')

    return params unless global_config['ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT']

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end
end
