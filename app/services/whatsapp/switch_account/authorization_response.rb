# chat#1217 — Prepend em Api::V1::Accounts::Whatsapp::AuthorizationsController.
# - Sucesso: diz se a caixa ficou pronta para receber mensagens. A assinatura do webhook falha em silêncio
#   (Channel::Whatsapp#setup_webhooks marca reauthorization_required e segue), e a tela não pode dizer
#   "Pronto" nesse caso.
# - Erro: acrescenta error_code quando o número devolvido pelo Facebook não é o da caixa.
module Whatsapp::SwitchAccount::AuthorizationResponse
  private

  def render_success_response(inbox)
    return super if params[:inbox_id].blank?

    render json: {
      success: true,
      id: inbox.id,
      name: inbox.name,
      channel_type: 'whatsapp',
      message: I18n.t('inbox.reauthorization.success'),
      ready_to_receive: !inbox.channel.reauthorization_required?
    }
  end

  def render_embedded_signup_error(error)
    return super unless error.is_a?(Whatsapp::SwitchAccount::PhoneNumberMismatchError)

    Rails.logger.warn("[WHATSAPP SWITCH ACCOUNT] phone_number_mismatch inbox_id=#{params[:inbox_id]}")
    render json: {
      success: false,
      error: error.message,
      error_code: Whatsapp::SwitchAccount::PhoneNumberMismatchError::ERROR_CODE,
      expected_phone_number: error.expected,
      received_phone_number: error.received
    }, status: :unprocessable_entity
  end
end
