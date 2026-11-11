# #2858 F5 — a rodada diária das bases baixadas (config/schedule.yml): enfileira a importação de cada base que passou da
# hora (`Importador.vencida?`: a diária, uma vez por dia; a mensal, a cada 28 dias). A base que falhou tenta de novo na
# rodada seguinte, com a cópia anterior valendo até lá. Sem nenhuma conta com a flag das bases, não baixa nada.
class Autonomia::FerramentasProntas::AtualizarBasesJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  def perform
    return unless Autonomia::FerramentasProntas::Bases.em_uso?

    Autonomia::FerramentasProntas::Bases.importadores.each do |importador|
      estado = Autonomia::FerramentasProntas::Bases::Estado.de(importador.chave)
      Autonomia::FerramentasProntas::AtualizarBaseJob.perform_later(importador.chave) if importador.vencida?(estado)
    end
  end
end
