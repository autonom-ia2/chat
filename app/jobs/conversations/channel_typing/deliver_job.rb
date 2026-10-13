# chat#1442 — A chamada ao canal sai do request: o HTTParty dos serviços de canal não tem timeout, e a
# toggle_typing_status do robô não pode esperar a Meta.
class Conversations::ChannelTyping::DeliverJob < ApplicationJob
  queue_as :high

  def perform(conversation, typing_status)
    Conversations::ChannelTyping::Deliverer.new(conversation: conversation, typing_status: typing_status).perform
  end
end
