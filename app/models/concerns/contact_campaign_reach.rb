# Quem pode receber campanha (chat#2733). Uma regra só, para todos os canais (WhatsApp oficial, WhatsApp API, SMS e
# e-mail): não recebe quem recusou mensagens ativas (ContactOptOut, chat#737) nem quem está bloqueado (`blocked`).
# Vale ao montar o Público e de novo no envio, pessoa por pessoa: bloqueado depois de salvar o Público também não recebe.
#
# campaign_refusal dá o motivo gravado no destinatário pulado: 'opted_out' antes de 'blocked' (quem tem os dois conta
# como recusa, o motivo que já existia).
module ContactCampaignReach
  extend ActiveSupport::Concern

  OPTED_OUT = 'opted_out'.freeze
  BLOCKED = 'blocked'.freeze

  included do
    scope :campaign_reachable, -> { not_opted_out.where(blocked: false) }
    scope :campaign_unreachable, -> { opted_out.or(where(blocked: true)) }
  end

  class_methods do
    # O motivo relido do banco, para o envio conferir pessoa por pessoa logo antes de cada mensagem: quem recusou ou
    # foi bloqueado durante o disparo não recebe. nil = pode receber.
    def campaign_refusal_now(contact_id)
      select(:id, :opted_out_at, :blocked).find_by(id: contact_id)&.campaign_refusal
    end
  end

  def campaign_refusal
    return OPTED_OUT if opted_out?

    BLOCKED if blocked?
  end
end
