class Instagram::Messenger::SendOnInstagramService < Instagram::BaseSendService
  private

  def channel_class
    Channel::FacebookPage
  end

  # Deliver a message with the given payload.
  # A citação (reply_to, #2113) nesta caixa só chega pela API ou por um AgentBot: o painel não mostra "Responder"
  # na caixa da página do Facebook (o tipo FB fica fora de REPLY_TO_OUTGOING).
  # @see https://developers.facebook.com/docs/messenger-platform/instagram/features/send-message
  def send_message(message_content)
    access_token = channel.page_access_token
    app_secret_proof = calculate_app_secret_proof(GlobalConfigService.load('FB_APP_SECRET', ''), access_token)
    query = { access_token: access_token }
    query[:appsecret_proof] = app_secret_proof if app_secret_proof

    response = HTTParty.post(
      'https://graph.facebook.com/v11.0/me/messages',
      body: message_content,
      query: query
    )

    process_response(response, message_content)
  end

  def calculate_app_secret_proof(app_secret, access_token)
    Facebook::Messenger::Configuration::AppSecretProofCalculator.call(
      app_secret, access_token
    )
  end

  def merge_human_agent_tag(params)
    return params unless human_agent_tag?('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT')

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end
end
