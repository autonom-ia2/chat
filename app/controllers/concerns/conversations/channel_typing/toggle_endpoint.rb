# chat#1442 — Prepend em Api::V1::Accounts::ConversationsController.
# toggle_typing_status segue igual (evento para o painel e webhooks). Só quando a chamada traz
# deliver_to_channel — campo que só o robô envia — o "digitando" também vai ao canal da conversa.
# Atendente digitando no painel não envia o campo: nada chega ao cliente nem marca mensagem como lida.
module Conversations::ChannelTyping::ToggleEndpoint
  def toggle_typing_status
    super
    return unless ActiveModel::Type::Boolean.new.cast(params[:deliver_to_channel])
    return unless Conversations::ChannelTyping::Deliverer.supports?(@conversation)

    Conversations::ChannelTyping::DeliverJob.perform_later(@conversation, params[:typing_status])
  end
end
