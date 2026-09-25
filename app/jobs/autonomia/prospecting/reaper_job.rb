# Varredor da fila da Prospecção (#678). Um worker que morre no meio (deploy, OOM) deixa o lead "em andamento"
# para sempre: a tela recusa pedido novo e ninguém o marca como falho. A cada rodada, o que passou de
# LeadWorkQueue::STALE_AFTER volta a um estado retomável e a tela é avisada.
class Autonomia::Prospecting::ReaperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    reap_enrichment
    reap_whatsapp
  end

  private

  def reap_enrichment
    stale = Autonomia::Prospecting::Lead.where(
      enrichment_status: Autonomia::Prospecting::LeadWorkQueue::IN_PROGRESS,
      enrichment_requested_at: ...cutoff
    )
    stale.find_each do |lead|
      reaped = Autonomia::Prospecting::Lead.where(id: lead.id, enrichment_status: lead.enrichment_status).update_all( # rubocop:disable Rails/SkipsModelValidations
        enrichment_status: 'failed', enrichment_completed_at: Time.current, updated_at: Time.current,
        enrichment_error: Autonomia::Prospecting::EnrichLeadJob::INTERRUPTED
      )
      Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload) if reaped.positive?
    end
  end

  # Sem status, o lead volta a ser verificado pela próxima busca ou pela aba aberta.
  def reap_whatsapp
    stale = Autonomia::Prospecting::Lead
            .where("metadata -> 'whatsapp_verification' ->> 'status' = 'queued'")
            .where("(metadata -> 'whatsapp_verification' ->> 'queued_at')::timestamptz < ?", cutoff)
    stale.find_each do |lead|
      Autonomia::Prospecting::Lead.where(id: lead.id)
                                  .update_all(["metadata = metadata - 'whatsapp_verification', updated_at = ?", Time.current]) # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload)
    end
  end

  def cutoff
    @cutoff ||= Autonomia::Prospecting::LeadWorkQueue::STALE_AFTER.ago
  end
end
