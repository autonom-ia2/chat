# Reaper de rascunhos ÓRFÃOS do Construtor. Causa-raiz do vazamento que o KB-first (§9) introduz: com
# opt-in de base o rascunho nasce ANTES do chat (para a etapa de anexar materiais ter agentId), então
# abrir o Construtor e sair deixa um agente "Novo agente" vazio pendurado no Hub. Também limpa o leak
# pré-existente (rascunhos abandonados após o 1º turno), que nunca teve cleanup.
#
# Varre agentes GUIADOS ainda em `draft` + `enabled:false`, SEM instrução e SEM fonte (#1035), cuja
# última atividade — do próprio agente e de qualquer build thread — é mais velha que a janela, e os
# arquiva sem apagar o agente nem desvincular as threads.
# Escopo estreito (guided + draft + disabled + vazio) nunca toca agente ativo/pausado, manual, pronto
# para publicar ou com materiais.
#
# Janela ampla (48h default, ajustável por ENV) protege rascunho em construção lenta: qualquer
# geração/edição toca o updated_at do agente ou da thread e reabre a janela; um upload tira o
# rascunho da varredura de vez.
# Idempotente; recheck sob lock por registro (defesa em job destrutivo); cap por execução evita pico
# de exclusão. Roda de tempos em tempos (schedule.yml).
class Autonomia::Agents::ReapStaleDraftsJob < ApplicationJob
  queue_as :scheduled_jobs

  DEFAULT_STALE_HOURS = 48
  BATCH_LIMIT = 500

  def perform
    cutoff = stale_hours.hours.ago
    reaped = stale_drafts(cutoff).limit(BATCH_LIMIT).count { |agent| reap_if_still_stale(agent, cutoff) }
    return unless reaped.positive?

    Rails.logger.info("[Autonomia::ReapStaleDrafts] reaped=#{reaped} cutoff=#{cutoff.iso8601}")
  end

  private

  # Recheca o critério sob lock antes de destruir: entre a seleção e o destroy o dono pode ter
  # retomado (nova geração/upload). Só apaga se o registro AINDA casar como órfão.
  def reap_if_still_stale(agent, cutoff)
    agent.with_lock do
      next false unless stale_drafts(cutoff).exists?(agent.id)

      Autonomia::Agents::SoftDelete.new(agent: agent, actor: nil, reason: 'stale_draft').perform
    end
  end

  # Rascunhos guiados órfãos: draft + desabilitado + VAZIOS (sem instrução e sem nenhuma fonte) +
  # updated_at velho + sem atividade recente em thread. #1035: o Construtor não muda o status ao
  # terminar, então rascunho com instrução é agente PRONTO aguardando publicação, e rascunho com
  # material é trabalho do dono — nenhum dos dois é vazamento. Só o "Novo agente" vazio é. (Com
  # `where.missing(:sources)` a antiga proteção de "fonte recente" ficou contida nesta.)
  def stale_drafts(cutoff)
    Autonomia::Agents::Agent
      .kept.guided.draft.where(enabled: false)
      .where(instruction: [nil, ''])
      .where.missing(:sources)
      .where('autonomia_agents.updated_at < ?', cutoff)
      .where.not(id: recent_activity_agent_ids(Autonomia::Agents::BuildThread, cutoff))
  end

  # IDs de agente com atividade recente na relação dada. where.not(autonomia_agent_id: nil) é
  # OBRIGATÓRIO: a thread nasce antes do agente (agent_id nil), e um NULL na subquery de um
  # `id NOT IN (...)` tornaria o predicado UNKNOWN, zerando toda a varredura.
  def recent_activity_agent_ids(relation, cutoff)
    relation.where('updated_at >= ?', cutoff)
            .where.not(autonomia_agent_id: nil)
            .select(:autonomia_agent_id)
  end

  # Janela positiva sempre: 0/negativo (cutoff no futuro varreria rascunhos demais) cai no default.
  def stale_hours
    hours = Integer(ENV.fetch('AUTONOMIA_DRAFT_REAP_HOURS', DEFAULT_STALE_HOURS))
    hours.positive? ? hours : DEFAULT_STALE_HOURS
  rescue ArgumentError, TypeError
    DEFAULT_STALE_HOURS
  end
end
