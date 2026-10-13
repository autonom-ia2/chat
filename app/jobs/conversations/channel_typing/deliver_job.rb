# chat#1442 — A chamada ao canal sai do request: os serviços de canal usam HTTParty sem timeout próprio,
# o que deixa valer o padrão do Net::HTTP (60 s para abrir e 60 s para ler), e a toggle_typing_status do
# robô não pode esperar a Meta.
# Fila medium: atrás da high, que envia as respostas (SendReplyJob), e a mesma da entrega do agente nativo.
# No job a chamada ao canal é limitada a CHANNEL_TIMEOUT_SECONDS, para não prender thread da fila.
# "Digitando" que chega tarde é pior que não chegar: o pedido é descartado (com log) quando ficou mais
# velho que MAX_AGE, ou quando é um "on" e a resposta já saiu — ele reacenderia o indicador.
class Conversations::ChannelTyping::DeliverJob < ApplicationJob
  queue_as :medium

  MAX_AGE = 10.seconds
  CHANNEL_TIMEOUT_SECONDS = 3

  def perform(conversation, typing_status, requested_at)
    reason = drop_reason(conversation, typing_status, requested_at)
    return log_drop(conversation, typing_status, requested_at, reason) if reason

    Conversations::ChannelTyping::Deliverer.new(conversation: conversation, typing_status: typing_status, timeout: CHANNEL_TIMEOUT_SECONDS).perform
  end

  private

  def drop_reason(conversation, typing_status, requested_at)
    return 'stale' if requested_at < MAX_AGE.ago

    'already_replied' if typing_status == 'on' && replied_since?(conversation, requested_at)
  end

  def replied_since?(conversation, requested_at)
    conversation.messages.outgoing.exists?(private: false, created_at: requested_at..)
  end

  def log_drop(conversation, typing_status, requested_at, reason)
    age = (Time.current - requested_at).round
    Rails.logger.info("[channel_typing] dropped conversation=#{conversation.id} status=#{typing_status} reason=#{reason} age_seconds=#{age}")
  end
end
