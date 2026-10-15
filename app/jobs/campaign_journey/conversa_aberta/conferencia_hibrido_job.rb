# Confere de novo o envio do WhatsApp Híbrido que ficou `throttled` na queda do 131047 (#1453). Relê a Message do banco
# (CampaignJourney::ConversaAberta::QuedaHibrido): `failed` pede o modelo; `accepted`/`uncertain` encerram; ainda
# `throttled` agenda outra conferência, com espera crescente, até TENTATIVAS, e depois desiste com log. Entrega que já
# caiu para o modelo (fell_back_at) não é conferida: o modelo sai uma vez só.
class CampaignJourney::ConversaAberta::ConferenciaHibridoJob < ApplicationJob
  queue_as :low

  TENTATIVAS = 3
  # Esperas de 30, 60 e 120 s: as conferências rodam ~30, 90 e 210 s depois do aviso. O Híbrido tenta de novo a cada 15 s
  # (com teto próprio, WebTransport::THROTTLE_MAX_RETRIES); a falha final dele também pede o modelo, pelo WebTransport.
  ESPERA = 30.seconds

  def perform(delivery_id, tentativa)
    delivery = CampaignFreeTextDelivery.find_by(id: delivery_id, fell_back_at: nil)
    CampaignJourney::ConversaAberta::QuedaHibrido.new(delivery).seguir(tentativa) if delivery
  end
end
