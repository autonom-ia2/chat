# #1593 — cenário real para os specs do CRM que oferecem agentes de IA (Atribuição, pedido pelo nome, "Passar para…").
# Quem pode receber é a regra dos Agentes (Autonomia::Agents::PassarParaIa.destinos_*): a conta com os Agentes e a
# Fase 2 ligados, e o agente trabalhando na caixa. Nada dublado no serviço.
module PassarParaIaHelper
  def criar_agente_ia(account, nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end

  # Os Agentes e a Fase 2 ligados nesta conta.
  def ligar_agentes_ia!(account)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
  end

  # O agente atendendo a caixa (a porta dela, pelo InboxConnector): passa a ser destino das conversas dali.
  def agente_na_caixa!(agente, inbox)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: inbox).perform(connect: true).agent_inbox
  end
end

RSpec.configure { |config| config.include PassarParaIaHelper }
