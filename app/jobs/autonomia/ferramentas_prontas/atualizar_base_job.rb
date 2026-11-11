# #2858 F5 — a importação de UMA base (`Bases::Importacao`), na fila baixa: o download grande (até ~160 MB) e o COPY não
# seguram as filas do atendimento. Sem nova tentativa automática: a falha já guardou o motivo, mandou o alerta e deixou
# a cópia anterior valendo; a próxima rodada diária tenta de novo.
class Autonomia::FerramentasProntas::AtualizarBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(chave)
    importador = Autonomia::FerramentasProntas::Bases.buscar(chave)
    return if importador.nil? || !Autonomia::FerramentasProntas::Bases.em_uso?

    Autonomia::FerramentasProntas::Bases::Importacao.new(importador).call
  end
end
