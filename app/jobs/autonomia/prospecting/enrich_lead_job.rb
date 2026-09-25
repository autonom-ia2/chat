# Enriquecimento de um lead fora da requisição (#678). O pedido já foi aceito por LeadWorkQueue.enqueue_enrichment,
# que deixou o lead em queued; este job só roda o que ainda está na fila.
class Autonomia::Prospecting::EnrichLeadJob < ApplicationJob
  queue_as :prospecting

  INTERRUPTED = 'prospecting.enrichment.interrupted'.freeze

  def perform(lead_id)
    lead = Autonomia::Prospecting::Lead.find_by(id: lead_id)
    return unless lead&.enrichment_queued?

    enrich(lead)
    Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload)
  end

  private

  # Sem relançar: o Sidekiq refaria site + IA de um lead que já está marcado como falho. A falha fica no lead
  # (failed), que aceita um pedido novo.
  def enrich(lead)
    Autonomia::Prospecting::LeadEnricher.new(lead: lead, user: nil).perform
    verify_site_whatsapp(lead.reload)
  rescue Autonomia::Prospecting::LeadEnricher::Error
    nil
  rescue StandardError => e
    Rails.logger.warn("[Autonomia::Prospecting::EnrichLeadJob] lead_id=#{lead.id} interrupted error=#{e.class.name}")
    lead.update_columns( # rubocop:disable Rails/SkipsModelValidations -- mesmo registro de falha do LeadEnricher#mark_failed
      enrichment_status: 'failed', enrichment_completed_at: Time.current, enrichment_error: INTERRUPTED, updated_at: Time.current
    )
  end

  def verify_site_whatsapp(lead)
    return unless Autonomia::Prospecting::LeadWorkQueue.site_whatsapp_pending?(lead)

    Autonomia::Prospecting::VerifyWhatsappJob.perform_later(lead.account_id, [lead.id])
  end
end
