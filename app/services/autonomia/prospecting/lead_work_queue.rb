# Fila do trabalho de cada lead da Prospecção (#678): enriquecimento e verificação de WhatsApp rodam no Sidekiq,
# não na requisição nem na aba aberta.
#
# A trava é o banco, não a memória do processo (há vários workers e vários pumas): o pedido só entra se a linha
# ainda não está na fila ou rodando. Uma linha rodando há mais de STALE_AFTER, ou na fila há mais de
# QUEUED_STALE_AFTER, conta como livre, e o ReaperJob a devolve a failed para a tela mostrar o botão de novo.
module Autonomia::Prospecting::LeadWorkQueue
  STALE_AFTER = 15.minutes
  # "queued" é o job esperando a vez na fila, não um worker morto: uma busca de 60 leads com site e IA, ou duas seguidas,
  # passa fácil de 15 minutos na fila. Só depois desta espera o pedido conta como perdido.
  QUEUED_STALE_AFTER = 2.hours
  IN_PROGRESS = %w[queued running].freeze
  WHATSAPP_BATCH_SIZE = 20
  WHATSAPP_RETRY_STATUSES = [nil, 'failed'].freeze

  module_function

  # true quando este pedido ficou com o lead; false quando outro já está na fila ou rodando.
  def enqueue_enrichment(lead)
    now = Time.current
    # rubocop:disable Rails/SkipsModelValidations -- trava atômica: só um pedido fica com o lead
    claimed = claimable(lead).update_all(enrichment_status: 'queued', enrichment_requested_at: now, enrichment_error: nil, updated_at: now)
    # rubocop:enable Rails/SkipsModelValidations
    return false if claimed.zero?

    Autonomia::Prospecting::EnrichLeadJob.perform_later(lead.id)
    true
  end

  # Disparo do servidor ao fim da busca: não depende da aba aberta. Enriquecer e pesquisar empresa e decisor é pesquisa
  # (só com a pesquisa ligada pelo superadmin, #683) e só para quem nunca passou por ela; verificar WhatsApp roda sempre
  # que o módulo está ligado e há sessão WAHA na conta.
  def after_search(account:, leads:)
    return unless Autonomia::Prospecting::Config.enabled?(account)

    leads.select(&:enrichment_pending?).each { |lead| enqueue_enrichment(lead) } if Autonomia::Prospecting::Config.research_enabled?(account)
    Autonomia::Prospecting::Research::Queue.after_search(account: account, leads: leads)
    enqueue_whatsapp(account, leads) if Autonomia::Prospecting::WhatsappVerifier.available_for?(account)
  end

  def enqueue_whatsapp(account, leads)
    pending = leads.select { |lead| whatsapp_pending?(lead) }
    return if pending.empty?

    mark_whatsapp_queued(pending.select { |lead| google_phone_pending?(lead) }.map(&:id))
    pending.map(&:id).each_slice(WHATSAPP_BATCH_SIZE) { |batch| Autonomia::Prospecting::VerifyWhatsappJob.perform_later(account.id, batch) }
  end

  def whatsapp_pending?(lead)
    google_phone_pending?(lead) || site_whatsapp_pending?(lead)
  end

  def google_phone_pending?(lead)
    lead.phone.present? && WHATSAPP_RETRY_STATUSES.include?(lead.metadata.to_h.dig('whatsapp_verification', 'status'))
  end

  def site_whatsapp_pending?(lead)
    lead.enriched_whatsapp.present? && WHATSAPP_RETRY_STATUSES.include?(lead.metadata.to_h.dig('site_whatsapp_verification', 'status'))
  end

  # A marca "queued" faz a tela não pedir a mesma verificação pela aba (useLeadWhatsApp pula quem já tem status)
  # e mostrar "Verificando". Gravada no jsonb sem reescrever o resto do metadata.
  def mark_whatsapp_queued(lead_ids)
    return if lead_ids.empty?

    marker = { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => Time.current.iso8601 } }
    Autonomia::Prospecting::Lead.where(id: lead_ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['metadata = metadata || ?::jsonb, updated_at = ?', marker.to_json, Time.current]
    )
  end

  def claimable(lead)
    scope = Autonomia::Prospecting::Lead.where(id: lead.id)
    scope.where.not(enrichment_status: IN_PROGRESS)
         .or(scope.where(enrichment_requested_at: nil))
         .or(scope.merge(stale_enrichment))
  end

  # Rodando há mais de STALE_AFTER é worker que morreu; na fila, só depois de QUEUED_STALE_AFTER.
  def stale_enrichment(now = Time.current)
    leads = Autonomia::Prospecting::Lead
    leads.where(enrichment_status: 'running', enrichment_requested_at: ...(now - STALE_AFTER))
         .or(leads.where(enrichment_status: 'queued', enrichment_requested_at: ...(now - QUEUED_STALE_AFTER)))
  end
end
