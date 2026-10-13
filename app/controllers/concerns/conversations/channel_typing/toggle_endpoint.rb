# chat#1442 — Prepend em Api::V1::Accounts::ConversationsController.
# toggle_typing_status segue igual (evento para o painel e webhooks). Quando a chamada traz
# deliver_to_channel verdadeiro, o "digitando" também vai ao canal da conversa. O painel não envia esse
# campo, então atendente digitando não chega ao cliente nem marca mensagem como lida; quem envia é o robô,
# com token de AgentBot ou de usuário.
# Nada daqui muda a resposta: o que não pode ir ao canal é ignorado, e falha ao enfileirar vira log.
module Conversations::ChannelTyping::ToggleEndpoint
  def toggle_typing_status
    super
    enqueue_channel_typing if channel_typing_requested?
  end

  private

  def channel_typing_requested?
    ActiveModel::Type::Boolean.new.cast(params[:deliver_to_channel]) &&
      !ActiveModel::Type::Boolean.new.cast(params[:is_private]) &&
      Conversations::ChannelTyping::Deliverer::SENDER_ACTIONS.key?(params[:typing_status]) &&
      channel_typing_caller_serves_inbox? &&
      Conversations::ChannelTyping::Deliverer.supports?(@conversation)
  end

  # A policy deixa um AgentBot ver qualquer conversa da conta; ao canal só vai o da caixa da conversa.
  def channel_typing_caller_serves_inbox?
    !Current.user.is_a?(AgentBot) || Current.user.inboxes.exists?(@conversation.inbox_id)
  end

  def enqueue_channel_typing
    Conversations::ChannelTyping::DeliverJob.perform_later(@conversation, params[:typing_status], Time.current)
  rescue StandardError => e
    Rails.logger.warn("[channel_typing] enqueue failed conversation=#{@conversation.id} #{e.class}")
  end
end
