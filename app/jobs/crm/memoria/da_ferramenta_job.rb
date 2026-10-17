# W5 (#1601): grava o resultado de uma execução de ferramenta concluída como fato confirmado do card.
class Crm::Memoria::DaFerramentaJob < ApplicationJob
  queue_as :low

  def perform(run_id)
    run = Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.nil? || run.status != 'done' || !Crm::Memoria.ligada?(run.account)

    Crm::Memoria::DaFerramenta.registrar!(run)
  end
end
