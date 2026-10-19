# Prepend em Api::V1::Accounts::ConversationsController (chat#1709, rodada de correção): a criação de conversa com
# mensagem (`message.content_attributes`) é a outra porta da API pública por onde alguém criaria mensagem com as chaves
# do contrato com o conector do WAHA. A mesma limpeza do `messages#create` (Waha::RichNative::ForgeryGuard.clean), com a
# caixa do pedido (a do `@contact_inbox` ou o `@inbox`, dos before_action originais). Entra como before_action, sem sobrescrever `create` (o Guia lê o
# formato da ação no método original). INCONDICIONAL, como a do `messages#create`.
module Waha::RichNative::ConversationForgeryGuard
  def self.prepended(controller)
    controller.before_action :drop_waha_contract_keys_from_message, only: :create
  end

  private

  def drop_waha_contract_keys_from_message
    message = params[:message]
    return unless message.respond_to?(:key?) && message.key?(:content_attributes)

    inbox = @contact_inbox&.inbox || @inbox
    incoming = message[:message_type].to_s == 'incoming'
    message[:content_attributes] = Waha::RichNative::ForgeryGuard.clean(message[:content_attributes], inbox: inbox, incoming: incoming)
  end
end
