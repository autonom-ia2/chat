# Mantém cada número no IP certo (#1516). A cada rodada busca cada plano da Webshare UMA vez e as sessões do motor UMA
# vez, e agenda a troca no motor (WhatsappProxy::ApplyJob, com espera e volta) para a sessão:
# - cujo IP saiu da lista (ou da fatia), ficou inválido ou mudou de credencial;
# - instável no motor com IP que a Webshare ainda chama de válido (WhatsappProxy::Health): o IP vai para quarentena por
#   24 h e o número ganha outro do mesmo plano e fatia — no máximo uma troca dessas por sessão por dia;
# - no plano ou na conta errada (número que trocou de tipo, WAHA ↔ Híbrido) — importada, só com
#   WHATSAPP_PROXY_AUTO_MIGRATE=true.
# No máximo MAX_CHANGES por rodada. IP que sumiu da lista é URGENTE (o número já está fora do ar: na ativação do "High IP
# Reputation" em 14/10/2026 três sessões ficaram em STARTING): troca já, sem espaçamento; as demais saem espaçadas.
# Sessão que o motor não tem fica de fora, e SCAN_QR_CODE (aparelho desvinculado) nunca é reparada; atribuição sem caixa
# é apagada.
class WhatsappProxy::ReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_CHANGES = 5
  SPACING = 2.minutes

  def perform
    assigner = WhatsappProxy::Assigner.new
    return unless assigner.enabled?

    managed = managed_assignments
    pending = managed.filter_map { |assignment| pending_change(assignment, assigner, engine_statuses) }
    return if pending.empty?

    warn_mass_change(pending, managed)
    scheduled = schedule(urgent_first(pending).first(MAX_CHANGES), assigner)
    Rails.logger.info("[whatsapp_proxy] reconciliação: pendentes=#{pending.size} agendadas=#{scheduled} limite=#{MAX_CHANGES}")
  rescue Webshare::Client::Error, Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] reconciliação interrompida: #{e.class}")
  end

  private

  # Status de cada sessão no motor, numa chamada só (memorizado na rodada).
  def engine_statuses
    @engine_statuses ||= Array(Waha::Client.new.list_sessions(all: true)).to_h { |session| [session['name'], session['status'].to_s] }
  end

  # IP sumido primeiro (o número já está fora do ar); o resto na ordem de atribuição.
  def urgent_first(pending)
    pending.sort_by.with_index { |(_assignment, _owner, reason), index| [reason == :gone ? 0 : 1, index] }
  end

  # Atribuições da Webshare cujo número ainda tem caixa; as sem dono são apagadas (IP volta ao plano).
  def managed_assignments
    WhatsappProxy::Assignment.where.not(webshare_proxy_id: nil).order(:assigned_at).to_a.select do |assignment|
      next true if WhatsappProxy::SessionOwner.find(assignment.session_name)

      Rails.logger.warn("[whatsapp_proxy] session=#{assignment.session_name} sem caixa: atribuição apagada")
      assignment.destroy!
      false
    end
  end

  # [assignment, dono, motivo] quando a sessão precisa trocar; nil quando está certa ou não está no motor.
  def pending_change(assignment, assigner, statuses)
    status = statuses[assignment.session_name]
    return if status.nil?
    return unlinked_device(assignment) if status == 'SCAN_QR_CODE'

    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    health = health_of(assignment, status)
    return [assignment, owner, :plan] if assignment.migratable_to?(owner)

    listed = WhatsappProxy::Assigner.listed(assigner.pool(assignment.pool), assignment)
    return [assignment, owner, :gone] if listed.nil?
    return [assignment, owner, :unstable] if health == :unstable

    [assignment, owner, :credential] if listed.credential_digest != assignment.credential_digest
  end

  # Aparelho desvinculado: não é o proxy; nunca reparar (o PUT reiniciaria a sessão à toa). Só avisa.
  def unlinked_device(assignment)
    health_of(assignment, 'SCAN_QR_CODE')
    nil
  end

  def health_of(assignment, status)
    health = WhatsappProxy::Health.observe!(assignment.session_name, status)
    if health == :scan_qr
      WhatsappProxy::Alert.notify!('aparelho_desvinculado', "session=#{assignment.session_name} pede QR (aparelho " \
                                                            'desvinculado): não é o proxy, nada foi trocado')
    end
    health
  end

  def schedule(batch, assigner)
    spaced = 0
    batch.count do |(assignment, owner, reason)|
      next false if reason == :unstable && !quarantine!(assignment, assigner)
      next false if assigner.resolve(assignment.session_name, owner, assigner.pool(owner.pool)).nil?

      wait = reason == :gone ? 0 : (spaced += 1) * SPACING
      WhatsappProxy::ApplyJob.set(wait: wait).perform_later(assignment.session_name)
      true
    end
  end

  # Sessão caindo e voltando com IP "válido": o IP sai de circulação e o número troca, uma vez por dia no máximo.
  def quarantine!(assignment, assigner)
    session = assignment.session_name
    unless WhatsappProxy::Health.claim_swap!(session)
      WhatsappProxy::Alert.notify!('sessao_instavel_de_novo', "session=#{session} segue instável depois de trocar de IP " \
                                                              'hoje: o problema não parece ser o proxy', level: :error)
      return false
    end

    WhatsappProxy::Quarantine.put!(assignment.proxy_address, "session=#{session} instável")
    WhatsappProxy::Health.reset!(session)
    assigner.pool(assignment.pool).forget_quarantine!
    WhatsappProxy::Alert.notify!('sessao_instavel_trocada', "session=#{session} instável em #{assignment.server}: trocando de IP")
    true
  end

  def warn_mass_change(pending, managed)
    gone = pending.count { |(_assignment, _owner, reason)| reason == :gone }
    return unless gone * 2 > managed.size

    WhatsappProxy::Alert.notify!('troca_em_massa', "#{gone} de #{managed.size} IPs atribuídos sumiram da lista da Webshare. " \
                                                   "Trocando no máximo #{MAX_CHANGES} por rodada.", level: :error)
  end
end
