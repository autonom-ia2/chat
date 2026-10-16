# Reagir pelo painel a uma mensagem da caixa WAHA comum (chat#1709, fase 3).
#   POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/reaction  { "emoji": "👍" }
# Emoji vazio remove a reação do atendente. Só com a flag `whatsapp_rich_native` e motor que declara `react`
# (Waha::RichNative::MessageActions); a reação vai ao WhatsApp pelo conector customizado.
class Api::V1::Accounts::Conversations::MessageReactionsController < Api::V1::Accounts::Conversations::BaseController
  def create
    return head :forbidden unless Current.user.is_a?(User)

    error = Waha::RichNative::MessageActions.react!(message, user: Current.user, emoji: params[:emoji].to_s)
    return head :forbidden if error == :forbidden
    return render json: { error: I18n.t('waha.message_actions.reaction_invalid') }, status: :unprocessable_entity if error

    render json: { id: message.id, reactions: message.content_attributes.to_h['reactions'] || [] }
  end

  private

  def message
    @message ||= @conversation.messages.find(params[:id])
  end
end
