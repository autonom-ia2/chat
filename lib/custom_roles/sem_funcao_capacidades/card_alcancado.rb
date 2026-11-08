# Premissas "ve_o_card" (o OSS Crm::CardPolicy#show? pergunta ao visible_scope) e "participa_da_coluna"
# (Crm::CardPolicy#funnel_member?, Crm::Access::CardGuard) do contrato Sem função (#2308): iguais com e sem função.
class CustomRoles::SemFuncaoCapacidades::CardAlcancado < Crm::CardPolicy
  NO_ALCANCE = Class.new { def exists?(**) = true }.new.freeze

  private

  def visible_scope
    NO_ALCANCE
  end

  def funnel_member?
    true
  end
end
