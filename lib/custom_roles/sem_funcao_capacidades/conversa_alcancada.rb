# Premissa "na_caixa" do contrato Sem função (#2308): a conversa está numa caixa ou time da pessoa e nenhum funil a
# esconde. É a mesma pergunta para quem tem e quem não tem função (ConversationPolicy#agent_can_view_conversation?,
# Crm::Access::ConversationScope); o resto da policy, que muda com a função, é perguntado de verdade.
class CustomRoles::SemFuncaoCapacidades::ConversaAlcancada < ConversationPolicy
  private

  def agent_can_view_conversation?
    true
  end
end
