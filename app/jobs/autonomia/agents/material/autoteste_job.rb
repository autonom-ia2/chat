# #1426 (tema 4b) — roda uma rodada do autoteste (Material::Autoteste). Sem nova tentativa: a rodada que falha fica
# "parado" e a pessoa tenta de novo pela tela (repetir sozinho gastaria de novo). Fora da Fase 2 ou na Lia, nada.
class Autonomia::Agents::Material::AutotesteJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(agent_id, rodada)
    agent = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return unless Autonomia::Agents::Material.conferir?(agent)

    Autonomia::Agents::Material::Autoteste.new(agent, rodada).rodar!
  end
end
