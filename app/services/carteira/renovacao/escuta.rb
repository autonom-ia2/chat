# O que a carteira ouve do CRM (E5, #2898): o desfecho do card de renovação. O emissor do CRM
# (Crm::Webhooks::Emitter) só despacha o evento do card quando alguém o assina; a conta sem webhook, sem anúncio e sem
# automação nunca despacharia, e "Renovou" no quadro não chegaria ao seguro. Aqui o emissor pergunta se o card é de um
# seguro: uma leitura pelo índice único de `crm_card_id`, só nos eventos de desfecho.
module Carteira::Renovacao::Escuta
  EVENTOS = [Events::Types::CRM_CARD_WON, Events::Types::CRM_CARD_LOST, Events::Types::CRM_CARD_RESOLVED,
             Events::Types::CRM_CARD_CANCELLED, Events::Types::CRM_CARD_REOPENED, Events::Types::CRM_CARD_ARCHIVED].freeze

  def self.assinante?(evento, card_id:)
    EVENTOS.include?(evento) && Carteira::Apolice.exists?(crm_card_id: card_id)
  end
end
