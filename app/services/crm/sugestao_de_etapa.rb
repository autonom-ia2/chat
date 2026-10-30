# Quem lê a sugestão de etapa da IA (#2150, decisão do Rodrigo em 23/10): só quem tem `crm_manage_ai`, a chave de
# aceitar e dispensar. A regra mora em Crm::AiStageSuggestionPolicy#read? (no Enterprise, CrmPermissions): o
# administrador lê; o agente sem função não (crm_manage_ai está em PLAIN_AGENT_DENIED_KEYS); a função, só com
# crm_manage_ai ou crm_admin. No OSS, como aceitar e dispensar, lê quem vê o card.
# Sem ela, o card do quadro sai sem ai_suggestion e o filtro "Pendente de IA" é ignorado, porque revelaria quais cards
# têm sugestão; o histórico do card sai sem o "ai_suggested". O GET current_ai_suggestion recusa em
# Crm::CardPolicy#current_ai_suggestion?.
#
#   Crm::SugestaoDeEtapa.le?(account_user) -> true | false
module Crm::SugestaoDeEtapa
  module_function

  def le?(account_user)
    return false if account_user.blank?

    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    Pundit.policy!(contexto, Crm::AiStageSuggestion).read?
  end
end
