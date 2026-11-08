class Instagram::BaseSendService < Base::SendOnChannelService
  pattr_initialize [:message!]

  private

  delegate :additional_attributes, to: :contact

  def perform_reply
    @quote_mid = quoted_message_mid
    send_attachments if message.attachments.present?
    send_content if message.content.present?
  rescue StandardError => e
    handle_error(e)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_message(with_quote(attachment_message_params(attachment)))
    end
  end

  def send_content
    send_message(with_quote(message_params))
  end

  # Responder citando (#2113): a Meta aceita "reply_to": { "mid": ... } no envio. Uma mensagem com anexos e texto
  # sai em várias partes; a citação vai só na primeira. Sem o mid da citada (ex.: mensagem que nunca chegou à Meta),
  # o campo não é enviado e a resposta sai como hoje. Mensagem que o cliente desfez (deleted) também não é citada: o mid
  # dela continua gravado, mas a Meta não tem mais a mensagem.
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api
  def with_quote(params)
    return params if @quote_mid.blank?

    mid = @quote_mid
    @quote_mid = nil
    params.merge(reply_to: { mid: mid })
  end

  def quoted_message_mid
    mid = message.content_attributes[:in_reply_to_external_id].presence
    return if mid.blank?
    return if message.conversation.messages.find_by(source_id: mid)&.deleted

    mid
  end

  # A doc da Meta não diz como ela responde a um mid que não aceita mais. Para a citação nunca derrubar uma resposta
  # que sairia sem ela, a parte recusada com reply_to é reenviada uma vez sem o campo. Token inválido (190) não é
  # problema da citação e vai direto para a falha.
  def resend_without_quote?(message_content, parsed_response)
    message_content.key?(:reply_to) && parsed_response.dig('error', 'code') != 190
  end

  def handle_error(error)
    ChatwootExceptionTracker.new(error, account: message.account, user: message.sender).capture_exception
  end

  # Uma decisão por mensagem (#2259): texto e cada anexo saem com a mesma tag, sem refazer as consultas.
  def human_agent_tag?(config_key)
    return @human_agent_tag if defined?(@human_agent_tag)

    @human_agent_tag = Meta::HumanAgentTag.apply?(message, config_key)
  end

  def message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        text: message.outgoing_content
      }
    }

    merge_human_agent_tag(params)
  end

  def attachment_message_params(attachment)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment.download_url
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  def process_response(response, message_content)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      message.update!(source_id: parsed_response['message_id'])
      parsed_response
    elsif resend_without_quote?(message_content, parsed_response)
      Rails.logger.warn("Instagram refused reply_to, resending without quote: #{external_error(parsed_response)}")
      send_message(message_content.except(:reply_to))
    else
      external_error = external_error(parsed_response)
      Rails.logger.error("Instagram response: #{external_error} : #{message_content}")
      Messages::StatusUpdateService.new(message, 'failed', external_error).perform
      nil
    end
  end

  def external_error(response)
    error_message = response.dig('error', 'message')
    error_code = response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid. This may be due to a password change,
    # removal of the connected app from Instagram account settings, or other reasons.
    channel.authorization_error! if error_code == 190

    "#{error_code} - #{error_message}"
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  # Methods to be implemented by child classes
  def send_message(message_content)
    raise NotImplementedError, 'Subclasses must implement send_message'
  end

  def merge_human_agent_tag(params)
    raise NotImplementedError, 'Subclasses must implement merge_human_agent_tag'
  end
end
