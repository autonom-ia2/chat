class Instagram::SendOnInstagramService < Instagram::BaseSendService
  # Indicador "digitando" do Instagram (sender_action typing_on/typing_off) para o id do contato.
  # Usado pela entrega humanizada do agente nativo (Autonomia). BEST-EFFORT: devolve nil em qualquer
  # erro/credencial ausente, sem levantar (typing é cosmético).
  def send_sender_action(recipient_id, action, timeout: nil)
    return if recipient_id.blank? || channel.blank?

    HTTParty.post(
      "#{channel.graph_base_uri}/#{channel.messages_node}/messages",
      body: { recipient: { id: recipient_id }, sender_action: action },
      query: { access_token: channel.access_token },
      **{ timeout: timeout }.compact
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

    # O host e o nó vêm do login da caixa (#2406): no login do Facebook, a Página.
    response = HTTParty.post(
      "#{channel.graph_base_uri}/#{channel.messages_node}/messages",
      body: message_content,
      query: query
    )

    process_response(response, message_content)
  end

  def merge_human_agent_tag(params)
    return params unless human_agent_tag?('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end
end
