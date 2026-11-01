# Apaga, em lotes, os registros da Automação livre com mais de Autonomia::Automacao::Registro::RETENCAO (#2414,
# F2 #2452). Agendado no config/schedule.yml, uma vez por dia.
class Autonomia::Automacao::LimparRegistrosJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 1000

  def perform
    ::Autonomia::Automacao::Registro.where(created_at: ...::Autonomia::Automacao::Registro::RETENCAO.ago).in_batches(of: LOTE).delete_all
  end
end
