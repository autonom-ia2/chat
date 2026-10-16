# A atribuição feita pelo rodízio nativo da caixa entra no registro de passagens com motivo próprio, `rodizio` (#1657):
# sem isso ela tinha o mesmo perfil (sem quem pediu) de uma automação, da Entrega ou da IA do CRM. A R13
# (Crm::Conversations::OutroCanal) só tira da conversa quem o rodízio pôs.
#
# Por prepend (config/initializers/crm_passagens_rodizio.rb), sem tocar no Chatwoot:
# - Legado (V1): AgentAssignmentService#perform, a atribuição da conversa nova, com o save próprio.
# - Fila (V2, OSS e Enterprise): AssignmentService#claim_and_assign, a gravação da fila da caixa.
# A atribuição V1 dentro do save de quem reabre a conversa (#assign_under_lock) fica sem a marca: a troca é presa no
# save de quem chamou, e a R13 só olha conversa nova.
module Crm::Passagens::Rodizio
  MOTIVO = 'rodizio'.freeze

  module Legado
    def perform
      Crm::Passagens.com_motivo(Crm::Passagens::Rodizio::MOTIVO) { super }
    end
  end

  module Fila
    private

    def claim_and_assign(conversation, agent)
      Crm::Passagens.com_motivo(Crm::Passagens::Rodizio::MOTIVO) { super }
    end
  end
end
