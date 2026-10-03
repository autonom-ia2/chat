# Apaga o que o Guia fez há mais de 5 dias (#855). Passado o prazo, não há mais
# desfazer, e o "antes" guardado — que pode incluir dado de contato — não tem
# por que continuar no banco.
class Autonomia::Guide::LimparExecucoesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ::Autonomia::Guide::Execucao.where(expira_em: ..Time.current).in_batches(of: 500).delete_all
  end
end
