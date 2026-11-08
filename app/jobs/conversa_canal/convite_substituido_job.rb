# Marca o convite de reunião que ficou para trás (#1995, ConversaCanal::ConviteSubstituido), fora do recebimento do
# e-mail. Fila low: o cartão novo já aparece; o antigo para de perguntar em seguida.
class ConversaCanal::ConviteSubstituidoJob < ApplicationJob
  queue_as :low

  def perform(message)
    ConversaCanal::ConviteSubstituido.marcar(message)
  end
end
