# #1525 — o Agente de Cotação (Lia) nasce parado, pelo QuoteAgent::Builder, como todo agente externo. Spec que espera que
# ela responda liga-a a uma caixa na PREPARAÇÃO, como em produção: primeiro o vínculo, depois o agente ligado, a mesma
# ordem do InboxConnector com `ativar` (a validação de atender exige o vínculo). O espelho (`agent_bot`) é o que o spec já
# usa; o comportamento testado não muda.
module LiaNaCaixaHelper
  def lia_na_caixa(agente, inbox:, agent_bot:)
    vinculo = Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: agente.account, agent_bot: agent_bot)
    agente.update!(status: :active, enabled: true) unless agente.operating?
    vinculo
  end
end

RSpec.configure { |config| config.include LiaNaCaixaHelper }
