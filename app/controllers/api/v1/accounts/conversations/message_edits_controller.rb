# Editar pelo painel uma mensagem nossa da caixa WAHA comum (chat#1709, fase 3).
#   PATCH /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/content  { "content": "texto novo" }
# Só texto nosso, sem anexo nem formato, até 14 minutos depois do envio (o WhatsApp aceita 15), com até 4096
# caracteres. Só quem enviou a mensagem, ou um administrador da conta. Só com a flag `whatsapp_rich_native` e motor que
# declara `edit` (Waha::RichNative::MessageActions); a edição vai ao WhatsApp pelo conector customizado. O texto
# anterior fica em `edit_history`.
class Api::V1::Accounts::Conversations::MessageEditsController < Api::V1::Accounts::Conversations::BaseController
  def update
    return head :forbidden unless Current.user.is_a?(User)

    error = Waha::RichNative::MessageActions.edit!(message, user: Current.user, content: params[:content].to_s,
                                                            administrator: Current.account_user&.administrator? == true)
    return head :forbidden if error == :forbidden
    return render json: { error: I18n.t('waha.message_actions.edit_not_author') }, status: :forbidden if error == :not_author
    return render json: { error: invalid_text }, status: :unprocessable_entity if error

    render json: { id: message.id, content: message.content, content_attributes: message.content_attributes }
  end

  private

  def message
    @message ||= @conversation.messages.find(params[:id])
  end

  def invalid_text
    I18n.t('waha.message_actions.edit_invalid', minutes: Waha::RichNative::MessageActions::EDIT_WINDOW.in_minutes.to_i,
                                                max_length: Waha::RichNative::Edits::MAX_LENGTH)
  end
end
