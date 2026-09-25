# Fila da pesquisa de empresa e decisor (#679). Porta o contrato "all-N" da fila do Orth (research-queue.ts): cada lead
# que a busca devolveu entra uma vez, e repetir o disparo não duplica.
#
# A trava é o banco (vários workers e vários pumas): o pedido só entra se o lead não está na fila, em pesquisa ou
# esperando a vez da empresa. Pedido preso além da espera máxima conta como livre, e o ReaperJob o devolve a failed.
module Autonomia::Prospecting::Research::Queue
  States = Autonomia::Prospecting::Research::States
  STALE_AFTER = Autonomia::Prospecting::LeadWorkQueue::STALE_AFTER
  QUEUED_STALE_AFTER = Autonomia::Prospecting::LeadWorkQueue::QUEUED_STALE_AFTER
  INTERRUPTED = 'interrupted'.freeze

  module_function

  # Disparo automático ao fim da busca: uma pesquisa por lead nunca pesquisado. Quem já foi pesquisado se refaz pelo
  # "verificar novamente" do painel.
  def after_search(account:, leads:)
    return unless Autonomia::Prospecting::Config.research_enabled?(account)

    leads.uniq(&:id).select { |lead| lead.company_research_status == States::NOT_RESEARCHED }.each { |lead| enqueue(lead) }
  end

  # true quando este pedido ficou com o lead; false quando outro já está na fila, em pesquisa ou esperando a vez.
  def enqueue(lead, force: false)
    now = Time.current
    claimed = claimable(lead).update_all( # rubocop:disable Rails/SkipsModelValidations -- trava atômica: só um pedido fica com o lead
      company_research_status: States::QUEUED, decision_research_status: States::QUEUED, research_requested_at: now,
      research_started_at: nil, research_error: nil, updated_at: now
    )
    return false if claimed.zero?

    Autonomia::Prospecting::Research::ResearchJob.perform_later(lead.id, force)
    true
  end

  # Em pesquisa há mais de STALE_AFTER é worker que morreu; na fila ou esperando a vez, só depois de QUEUED_STALE_AFTER.
  def stale(now = Time.current)
    leads = Autonomia::Prospecting::Lead
    leads.where(company_research_status: States::RESEARCHING, research_started_at: ...(now - STALE_AFTER))
         .or(leads.where(company_research_status: [States::QUEUED, States::WAITING_CAPACITY], research_requested_at: ...(now - QUEUED_STALE_AFTER)))
  end

  # Barra de progresso da busca: "done" conta todo desfecho, inclusive falha; "failed" é a parte que falhou.
  def progress(leads)
    statuses = leads.map(&:company_research_status)
    {
      total: statuses.size,
      done: statuses.count { |status| States::TERMINAL.include?(status) },
      running: statuses.count(States::RESEARCHING),
      queued: statuses.count { |status| [States::QUEUED, States::WAITING_CAPACITY].include?(status) },
      failed: statuses.count('failed')
    }
  end

  def claimable(lead)
    scope = Autonomia::Prospecting::Lead.where(id: lead.id)
    scope.where.not(company_research_status: States::IN_PROGRESS).or(scope.merge(stale))
  end
end
