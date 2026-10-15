# Confere de novo o envio do WhatsApp Híbrido que ficou `throttled` na queda do 131047 (#1453). Relê a Message do banco
# (CampaignJourney::ConversaAberta::QuedaHibrido): `failed` pede o modelo; `accepted`/`uncertain` encerram; ainda
# `throttled` agenda a próxima conferência. A última roda depois do teto de novas tentativas do Híbrido
# (WhatsappHybrid::WebTransport::THROTTLE_MAX_RETRIES × 15 s ≈ 5 min): se ainda estiver `throttled`, fecha como falha e
# pede o modelo. Entrega que já caiu para o modelo (fell_back_at) não é conferida: o modelo sai uma vez só.
class CampaignJourney::ConversaAberta::ConferenciaHibridoJob < ApplicationJob
  queue_as :low

  # Conferências ~30 s, 2 min e 6 min depois do aviso; a última já passa do teto do Híbrido, com margem.
  ESPERAS = [30.seconds, 90.seconds, 240.seconds].freeze

  def perform(delivery_id, tentativa)
    delivery = CampaignFreeTextDelivery.find_by(id: delivery_id, fell_back_at: nil)
    CampaignJourney::ConversaAberta::QuedaHibrido.new(delivery).seguir(tentativa) if delivery
  end
end
