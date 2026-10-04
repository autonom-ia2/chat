# A cada 5 minutos, retoma a tarefa longa do Guia (#936) que ficou sem batimento: o processo morreu
# no meio de um lote (deploy, falta de memória). O lote seguinte pega só os itens pendentes.
class Autonomia::Guide::TarefasVigiaJob < ApplicationJob
  queue_as :scheduled_jobs

  SEM_BATIMENTO = 3.minutes

  def perform
    ::Autonomia::Guide::Tarefa.where(status: ::Autonomia::Guide::Tarefa::ANDANDO)
                              .where('batimento_em IS NULL OR batimento_em < ?', SEM_BATIMENTO.ago)
                              .find_each { |tarefa| ::Autonomia::Guide::TarefaJob.perform_later(tarefa.id) }
  end
end
