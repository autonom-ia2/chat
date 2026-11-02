# Uma rodada de uma execução da Automação livre (#2414 F3): ver Autonomia::Automacao::Executor.
#
# Sem nova tentativa do Sidekiq, de propósito: uma rodada que quebra no meio pode já ter feito passos, e repeti-la os
# faria de novo. Ela fica "andando", e a varredura a fecha como interrompida depois de 15 minutos (ADR-001 2.4).
class Autonomia::Automacao::AvancarJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(execucao_id, travada_em, raiz = nil)
    ::Autonomia::Automacao::Executor.rodar(execucao_id, travada_em, raiz)
  end
end
