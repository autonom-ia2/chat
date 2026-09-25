# ESBOÇO DO CONTRATO (#679): a frente B porta a regra do dono do Orth (owner-policy.ts). Este arquivo só existe para a
# frente C programar contra a assinatura; a integração troca pelo arquivo da frente B.
module Autonomia::Prospecting::Research::OwnerPolicy
  # owners: [{ name:, qualification: }] em ordem; decision: o primeiro ou nil; reason: código quando nil; evidence: :qsa ou :legal_name.
  Selection = Struct.new(:owners, :decision, :reason, :evidence, keyword_init: true)

  def self.select(company:, requested_role:)
    raise NotImplementedError, "frente B (#679) company=#{company.class} role=#{requested_role}"
  end
end
