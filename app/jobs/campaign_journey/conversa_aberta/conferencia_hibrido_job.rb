# Confere de novo o envio do WhatsApp Híbrido que ficou `throttled` na queda do 131047 (#1453). Relê a Message do banco
# (CampaignJourney::ConversaAberta::QuedaHibrido): `failed` pede o modelo; `accepted`/`uncertain` encerram; ainda
# `throttled` ou `pending` agenda a próxima conferência. Depois do teto de novas tentativas do Híbrido
# (WhatsappHybrid::WebTransport::THROTTLE_MAX_RETRIES × 15 s ≈ 5 min, mais folga) ainda `throttled`, ou na leitura tardia
# ainda `pending`, fecha sob trava (QuedaHibrido#fechar) e, se nada saiu, pede o modelo. Entrega que já caiu para o
# modelo (fell_back_at) não é conferida: o modelo sai uma vez só.
class CampaignJourney::ConversaAberta::ConferenciaHibridoJob < ApplicationJob
  queue_as :low

  # Conferências ~30 s, 2 min, 11 min e 16 min depois do aviso. A 3ª passa do teto do Híbrido (~5 min) com 5 min de
  # folga para a fila em rajada: ainda `throttled`, fecha. A 4ª é a leitura tardia de quem ficou `pending`.
  ESPERAS = [30.seconds, 90.seconds, 540.seconds, 300.seconds].freeze
  FECHA_THROTTLED = 3

  def perform(delivery_id, tentativa)
    delivery = CampaignFreeTextDelivery.find_by(id: delivery_id, fell_back_at: nil)
    CampaignJourney::ConversaAberta::QuedaHibrido.new(delivery).seguir(tentativa) if delivery
  end
end
