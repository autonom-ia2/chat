# Apaga os arquivos anexados na conversa com o Guia depois que o link deles venceu (#857). Passado
# esse prazo, nenhuma pergunta consegue mais lê-los, e o arquivo — que pode ter dado de cliente — não
# tem por que continuar guardado.
class Autonomia::Guide::LimparArquivosJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ::Autonomia::Guide::Arquivos.vencidos.find_each(&:purge)
  end
end
