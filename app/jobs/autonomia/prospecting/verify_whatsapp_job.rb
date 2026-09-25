# Verificação de WhatsApp em lote no servidor (#678): o telefone do Google e o WhatsApp achado no site, lead a lead,
# um lote por vez em cada conta (a sessão WAHA é uma só; consulta em rajada num número é o que o WhatsApp pune).
class Autonomia::Prospecting::VerifyWhatsappJob < MutexApplicationJob
  queue_as :prospecting

  # 20 leads x até 2 números x timeout do WAHA (20 s) no pior caso; a trava expira sozinha se o worker morrer.
  LOCK_TIMEOUT = 15.minutes
  retry_on_lock_conflict wait: 30.seconds, attempts: 40

  def perform(account_id, lead_ids)
    with_lock("autonomia:prospecting:whatsapp:#{account_id}", LOCK_TIMEOUT) do
      Autonomia::Prospecting::Lead.where(account_id: account_id, id: lead_ids).find_each { |lead| verify(lead) }
    end
  end

  private

  def verify(lead)
    verify_source(lead, :google) if Autonomia::Prospecting::LeadWorkQueue.google_phone_pending?(lead) || google_queued?(lead)
    verify_source(lead, :site) if Autonomia::Prospecting::LeadWorkQueue.site_whatsapp_pending?(lead)
    Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload)
  end

  # Falha do WAHA fica gravada no lead pelo verificador; o resto do lote segue. Sem número válido não há o que
  # verificar: solta a marca de fila para a tela não ficar em "Verificando".
  def verify_source(lead, source)
    Autonomia::Prospecting::WhatsappVerifier.new(lead: lead, source: source).perform
  rescue Autonomia::Prospecting::WhatsappVerifier::Error => e
    Rails.logger.info("[Autonomia::Prospecting::VerifyWhatsappJob] lead_id=#{lead.id} source=#{source} error=#{e.message}")
    release_queued_marker(lead) if source == :google && google_queued?(lead.reload)
  end

  def google_queued?(lead)
    lead.metadata.to_h.dig('whatsapp_verification', 'status') == 'queued'
  end

  def release_queued_marker(lead)
    Autonomia::Prospecting::Lead.where(id: lead.id)
                                .update_all(["metadata = metadata - 'whatsapp_verification', updated_at = ?", Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end
end
