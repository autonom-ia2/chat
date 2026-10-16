# frozen_string_literal: true

# chat#1648 — a aba da caixa não pluga agente externo em caixa atendida por agente da plataforma. Prepend no fork; o
# controller do Chatwoot fica intacto.
Rails.application.config.to_prepare do
  unless Api::V1::Accounts::InboxesController <= Autonomia::Agents::CaixaSemAgenteExterno
    Api::V1::Accounts::InboxesController.prepend(Autonomia::Agents::CaixaSemAgenteExterno)
  end
end
