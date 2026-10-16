# Editar pelo painel uma mensagem nossa da caixa WAHA comum (chat#1709, fase 3).
#   PATCH /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/content  { "content": "texto novo" }
# Só texto nosso, sem anexo nem formato, até 14 minutos depois do envio (o WhatsApp aceita 15). Só com a flag
# `whatsapp_rich_native` e motor que declara `edit` (Waha::RichNative::MessageActions); a edição vai ao WhatsApp pelo
# conector customizado. O texto anterior fica em `edit_history`.
class Api::V1::Accounts::Conversations::MessageEditsController < Api::V1::Accounts::Conversations::BaseController
  def update
    return head :forbidden unless Current.user.is_a?(User)

    error = Waha::RichNative::MessageActions.edit!(message, user: Current.user, content: params[:content])
    return head :forbidden if error == :forbidden
    return render json: { error: I18n.t('waha.message_actions.edit_invalid') }, status: :unprocessable_entity if error

    render json: { id: message.id, content: message.content, content_attributes: message.content_attributes }
  end

  private

  def message
    @message ||= @conversation.messages.find(params[:id])
  end
end
