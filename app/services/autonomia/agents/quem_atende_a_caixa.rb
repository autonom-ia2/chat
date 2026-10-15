# chat#1648 — marcação por caixa: o LEITOR ÚNICO de "quais agentes da plataforma atendem esta caixa", para a aba
# "Agente externo" da caixa (QuemAtendeController) e para a recusa do set_agent_bot (CaixaSemAgenteExterno). Só
# vínculos não apagados (`kept`), de porta ou de área, da conta da caixa. Não depende da flag da jornada nem da Fase 2:
# a regra vale para todas as contas.
module Autonomia::Agents::QuemAtendeACaixa
  module_function

  # Porta primeiro, depois as áreas por nome.
  def agentes(inbox)
    vinculos(inbox).includes(:agent).to_a
                   .sort_by { |vinculo| [vinculo.porta? ? 0 : 1, vinculo.agent.name.to_s.downcase, vinculo.agent.id] }
                   .map { |vinculo| { id: vinculo.agent.id, name: vinculo.agent.name, papel: vinculo.papel } }
  end

  def vinculos(inbox)
    ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: inbox.id, account_id: inbox.account_id)
  end

  # O espelho da porta ativa: o único AgentBot que a caixa com agente da plataforma aceita como robô.
  def espelho_da_porta(inbox)
    vinculos(inbox).porta.pick(:agent_bot_id)
  end
end
