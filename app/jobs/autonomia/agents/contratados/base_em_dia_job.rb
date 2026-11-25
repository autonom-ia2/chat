# De hora em hora (schedule.yml): o contratado com a base de outra versão (o deploy mudou um arquivo de `base/`, ou a
# semeadura falhou) entra na fila da semeadura. Só enfileira; quem confere de novo, sob a trava, é o `SemearBaseJob`.
class Autonomia::Agents::Contratados::BaseEmDiaJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    desatualizados.find_each do |agente|
      Autonomia::Agents::Contratados::SemearBaseJob.perform_later(agente.id)
    end
  end

  private

  def desatualizados
    Autonomia::Agents::Agent.kept
                            .where("config->'#{Autonomia::Agents::Contratados::MARCA}'->>'modelo' IN (?)",
                                   Autonomia::Agents::Contratados::MODELOS.keys)
                            .where("config->>'#{Autonomia::Agents::Contratados::BASE_VERSAO}' IS DISTINCT FROM ?",
                                   Autonomia::Agents::Contratados::Base::VERSAO)
  end
end
