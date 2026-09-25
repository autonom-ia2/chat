# Varredor da fila da Prospecção (#678). Um worker que morre no meio (deploy, OOM) deixa o lead "em andamento"
# para sempre: a tela recusa pedido novo e ninguém o marca como falho. A cada rodada, o que está rodando há mais de
# LeadWorkQueue::STALE_AFTER, ou na fila há mais de QUEUED_STALE_AFTER, volta a um estado retomável e a tela é avisada.
# "queued" é só o job esperando a vez: falhar isso cedo marcava como falho lead que nunca foi tentado.
class Autonomia::Prospecting::ReaperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    reap_enrichment
    reap_research
    reap_whatsapp
  end

  private

  def reap_enrichment
    Autonomia::Prospecting::LeadWorkQueue.stale_enrichment.find_each do |lead|
      reaped = Autonomia::Prospecting::Lead.where(id: lead.id, enrichment_status: lead.enrichment_status).update_all( # rubocop:disable Rails/SkipsModelValidations
        enrichment_status: 'failed', enrichment_completed_at: Time.current, updated_at: Time.current,
        enrichment_error: Autonomia::Prospecting::EnrichLeadJob::INTERRUPTED
      )
      Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload) if reaped.positive?
    end
  end

  # Pesquisa de empresa e decisor presa (#679): os dois estados voltam a failed, que aceita um pedido novo.
  def reap_research
    Autonomia::Prospecting::Research::Queue.stale.find_each do |lead|
      reaped = Autonomia::Prospecting::Lead.where(id: lead.id, company_research_status: lead.company_research_status).update_all( # rubocop:disable Rails/SkipsModelValidations
        company_research_status: 'failed', decision_research_status: 'failed', research_completed_at: Time.current,
        research_error: Autonomia::Prospecting::Research::Queue::INTERRUPTED, updated_at: Time.current
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

  # A marca de WhatsApp é sempre "queued": o job espera a trava da conta por até 20 minutos antes de rodar.
  def cutoff
    @cutoff ||= Autonomia::Prospecting::LeadWorkQueue::QUEUED_STALE_AFTER.ago
  end
end
