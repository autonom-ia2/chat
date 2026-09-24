# Aquece o Guia da Plataforma em todas as contas elegíveis depois de um deploy (#636).
#
# Hoje `Seed.ensure_async_for` só roda quando ALGUÉM usa o Guia: a primeira pergunta depois do
# deploy paga sozinha o custo da preparação (cache frio, `EnsureJob` na fila) e espera. Este job
# dispara essa preparação para TODA conta elegível, sozinho — a mesma ideia da Central de Ajuda em
# `config/initializers/central_de_ajuda.rb`.
#
# Não gera custo novo: `Seed.ensure_async_for` só reembeda quando o `kb_version` (hash do mapa +
# da instrução) muda, e o cache de 5 minutos dele evita enfileirar a mesma conta duas vezes — as
# duas instâncias do blue/green podem chamar este job sem duplicar trabalho.
class Autonomia::Guide::WarmUpJob < ApplicationJob
  queue_as :low

  def perform
    ::Account.find_each do |account|
      next unless ::Autonomia::Guide::Seed.eligible?(account)

      ::Autonomia::Guide::Seed.ensure_async_for(account)
    end
  end
end
