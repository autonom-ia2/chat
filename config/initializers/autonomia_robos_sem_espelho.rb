# frozen_string_literal: true

# chat#1626 — Configurações › Agentes externos não mostra nem deixa mexer no AgentBot espelho dos agentes da
# plataforma. Prepend no fork; o controller do Chatwoot fica intacto.
Rails.application.config.to_prepare do
  unless Api::V1::Accounts::AgentBotsController <= Autonomia::Agents::RobosSemEspelho
    Api::V1::Accounts::AgentBotsController.prepend(Autonomia::Agents::RobosSemEspelho)
  end
end
