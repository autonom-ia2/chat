# Quem entra na leitura automática do painel de desempenho (#2301). O mesmo critério vale ao enfileirar (o job da
# conta) e na hora de rodar (o job da ficha), que pode vir minutos depois, ou reagendado.
#
# - Conta: ativa, com a flag `agentes_painel_desempenho` e o módulo de Agentes ligados.
# - Agente: o robô de outro sistema só precisa existir na conta; o agente da plataforma, não apagado e ligado.
class Autonomia::Desempenho::LeituraAutomatica::Elegivel
  FLAG = 'agentes_painel_desempenho'.freeze

  def self.conta?(account)
    (account&.active? && account.feature_enabled?(FLAG) && ::Autonomia::Agents::Config.enabled?(account)) || false
  end

  def self.sujeito?(account, tipo, id)
    return AgentBot.exists?(account_id: account.id, id: id) if tipo == 'robo'

    ::Autonomia::Agents::Agent.kept.exists?(account_id: account.id, id: id, enabled: true)
  end
end
