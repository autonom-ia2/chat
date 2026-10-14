# Decide, numa rodada da reconciliação, o que fazer com cada atribuição (#1516). Devolve [motivo, urgente?] ou nil.
# Regras (caminhos tristes revisados):
# - sessão que o motor não tem, parada (STOPPED, desligada de propósito) ou pedindo QR (aparelho desvinculado) nunca é
#   tocada; a de QR entra no resumo diário;
# - em recuo de troca desfeita, espera (fora da conta das vagas da rodada);
# - pendente (nasceu sem proxy): :pending;
# - plano/conta errados (número que trocou de tipo) e credencial trocada: só com a sessão WORKING;
# - IP que sumiu da lista: urgente se a sessão também está fora de WORKING; se está WORKING, só depois de duas leituras
#   seguidas (GONE_CONFIRM) e sem urgência;
# - número irmão num IP em quarentena: troca se ele próprio está fora; WORKING, troca sem urgência (a rodada limita);
# - instável (WhatsappProxy::Health, só quem caiu de WORKING; nunca em falha geral; nunca sem a rodada anterior).
class WhatsappProxy::Triage
  OFF = WhatsappProxy::Health::UNSTABLE_STATUSES
  GONE_CONFIRM_TTL = 30.minutes.to_i

  def initialize(assigner:, outage:, statuses:)
    @assigner = assigner
    @outage = outage
    @statuses = statuses
  end

  def call(assignment)
    status = @statuses[assignment.session_name]
    return if status.nil? || status == 'STOPPED'
    return WhatsappProxy::Health.unlinked!(assignment.session_name) if status == 'SCAN_QR_CODE'

    health = health_of(assignment, status)
    return if assignment.in_backoff?
    return (status == 'WORKING' ? [:pending, false] : nil) if assignment.pending?

    decide(assignment, status, health)
  end

  private

  def decide(assignment, status, health)
    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    return (status == 'WORKING' ? [:plan, false] : nil) if assignment.migratable_to?(owner)

    ip_change(assignment, status) || ([:unstable, false] if health == :unstable) || credential_change(assignment, status)
  end

  def health_of(assignment, status)
    if @outage.general?(assignment.pool) || @outage.just_ended?(assignment.session_name)
      WhatsappProxy::Health.reset!(assignment.session_name)
      return
    end

    health = WhatsappProxy::Health.observe!(assignment.session_name, status,
                                            previous: @outage.previous_status(assignment.session_name))
    health if @outage.known?
  end

  def ip_change(assignment, status)
    pool = @assigner.pool(assignment.pool)
    return gone(assignment, status) unless pool.serving_ignoring_quarantine?(assignment.proxy_address, assignment.proxy_port)

    forget_gone(assignment)
    return unless pool.quarantined?(assignment.proxy_address)

    OFF.include?(status) ? [:quarantined, false] : [:quarantined_working, false]
  end

  # IP sumido: sessão fora troca já; sessão WORKING espera confirmar na rodada seguinte (lista instável da Webshare).
  def gone(assignment, status)
    return [:gone, true] if OFF.include?(status)
    return [:gone, false] if gone_seen_before?(assignment)

    nil
  end

  def gone_seen_before?(assignment)
    !::Redis::Alfred.set(gone_key(assignment), '1', nx: true, ex: GONE_CONFIRM_TTL)
  rescue Redis::BaseError
    false
  end

  def forget_gone(assignment)
    ::Redis::Alfred.delete(gone_key(assignment))
  rescue Redis::BaseError
    nil
  end

  def gone_key(assignment)
    "whatsapp_proxy:gone_seen:#{assignment.session_name}"
  end

  def credential_change(assignment, status)
    return unless status == 'WORKING'

    listed = WhatsappProxy::Assigner.listed(@assigner.pool(assignment.pool), assignment)
    [:credential, false] if listed && listed.credential_digest != assignment.credential_digest
  end
end
