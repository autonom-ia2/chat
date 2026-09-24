# Reaquece o Guia da Plataforma, nas contas que JÁ o usam, depois de um deploy que mudou o mapa ou
# a instrução (#636, revisão #637).
#
# Hoje `Seed.ensure_async_for` só roda quando ALGUÉM usa o Guia: a primeira pergunta depois do
# deploy paga sozinha o custo da preparação (cache frio, `EnsureJob` na fila) e espera. Este job
# dispara essa preparação sozinho — a mesma ideia da Central de Ajuda em
# `config/initializers/central_de_ajuda.rb`.
#
# SÓ para quem JÁ TEM o agente do Guia criado (revisão #637, HIGH): o embedding usa a chave de IA
# `crm_kanban_ai` DA CONTA — não é custo nosso. Rodar em `Account.find_each` (como a primeira
# versão fazia) gastaria a chave de TODA conta elegível, inclusive a que nunca abriu o painel do
# Guia; aquecer é reembedar uma base que já existe, não criar uma nova.
class Autonomia::Guide::WarmUpJob < ApplicationJob
  queue_as :low

  CACHE_PREFIX = 'autonomia:guide:aquecido:'.freeze

  def perform
    return unless reservar_varredura

    contas_com_guide.each { |account| aquecer(account) }
  end

  private

  # Uma varredura por versão do KB (revisão #637, MEDIUM): o blue/green sobe pelo menos duas
  # instâncias de Sidekiq, e cada uma dispara `on(:startup)` — sem isto, cada processo percorreria
  # as mesmas contas. `write` com `unless_exist: true` é o `SET ... NX` do Redis: atômico, só o
  # primeiro processo grava e só ele segue.
  def reservar_varredura
    Rails.cache.write("#{CACHE_PREFIX}#{::Autonomia::Guide::Seed.kb_version}", true, unless_exist: true)
  end

  # O mesmo escopo que `Seed#guide_agent_scope` usa para achar o agente do Guia de UMA conta
  # (`config->>'system_key' = 'platform_guide'`), só que para todas — sem repetir a lógica de
  # elegibilidade ou de dedupe, que já moram em `Seed`.
  def contas_com_guide
    agentes = ::Autonomia::Agents::Agent.where("config->>'system_key' = ?", ::Autonomia::Guide::Seed::SYSTEM_KEY)
    ::Account.where(id: agentes.select(:account_id).distinct)
  end

  # Erro de UMA conta não pode parar o laço das outras (revisão #637, MEDIUM) — mas também não pode
  # sumir calado: fica no log, como o `EnsureJob` já faz.
  def aquecer(account)
    return unless ::Autonomia::Guide::Seed.eligible?(account)

    ::Autonomia::Guide::Seed.ensure_async_for(account)
  rescue StandardError => e
    Rails.logger.error("[autonomia][guide][warm_up_job] account=#{account.id} #{e.class}: #{e.message}")
  end
end
