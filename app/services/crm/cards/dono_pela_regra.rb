# O dono do card que nasce sem conversa nem pessoa (G30, #2702, decisão do Rodrigo de 07/11, opção A): o lead do
# formulário do anúncio. Sem conversa não há caixa, presença nem fila de quem cuida, e a Atribuição (Crm::Entrega) não
# tem de onde escolher. Por isso só vale a escolha que não depende delas: a regra do funil ligada (a etapa vence o
# funil) apontando "A mesma pessoa" (pool_type 'user'). Rodízio, agente de IA, regra desligada ou pessoa que saiu da
# conta: sem dono, como antes.
module Crm::Cards::DonoPelaRegra
  module_function

  def de(account:, pipeline:, stage:)
    regra = Crm::Ai::Config.handoff_settings(stage, pipeline)
    return unless regra[:enabled] && regra[:pool_type] == 'user' && regra[:pool_id]

    account.users.find_by(id: regra[:pool_id])
  end
end
