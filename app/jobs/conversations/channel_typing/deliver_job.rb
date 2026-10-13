# chat#1442 — A chamada ao canal sai do request: os serviços de canal usam HTTParty sem timeout próprio,
# o que deixa valer o padrão do Net::HTTP (60 s para abrir e 60 s para ler), e a toggle_typing_status do
# robô não pode esperar a Meta.
# Fila medium: atrás da high, que envia as respostas (SendReplyJob), e a mesma da entrega do agente nativo.
# No job a chamada ao canal é limitada a CHANNEL_TIMEOUT_SECONDS, para não prender thread da fila.
# "Digitando" que chega tarde é pior que não chegar: pedido mais velho que MAX_AGE é descartado.
class Conversations::ChannelTyping::DeliverJob < ApplicationJob
  queue_as :medium

  MAX_AGE = 10.seconds
  CHANNEL_TIMEOUT_SECONDS = 3

  def perform(conversation, typing_status, requested_at)
    return if requested_at < MAX_AGE.ago

    Conversations::ChannelTyping::Deliverer.new(conversation: conversation, typing_status: typing_status, timeout: CHANNEL_TIMEOUT_SECONDS).perform
  end
end
