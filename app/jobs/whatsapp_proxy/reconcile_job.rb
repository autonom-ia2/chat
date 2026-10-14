# A Webshare troca IP morto e pode renovar a lista inteira (#1516): o motor ficaria apontando para um IP que não existe
# mais. A cada rodada busca cada plano UMA vez e a lista de sessões do motor uma vez, e agenda a troca no motor para a
# sessão cujo IP saiu da lista (ou da fatia), ficou inválido ou mudou de credencial; e para a que está no plano ou na
# conta errada (número que trocou de tipo: WAHA ↔ Híbrido) — esta, quando importada, só com
# WHATSAPP_PROXY_AUTO_MIGRATE=true. No máximo MAX_CHANGES por rodada, espaçadas, para nunca reiniciar todos os números
# de uma vez. Sessão que o motor não tem fica de fora; atribuição sem caixa no banco é apagada.
class WhatsappProxy::ReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_CHANGES = 5
  SPACING = 2.minutes

  def perform
    assigner = WhatsappProxy::Assigner.new
    return unless assigner.enabled?

    engine_names = Array(Waha::Client.new.list_sessions(all: true)).pluck('name')
    managed = managed_assignments
    pending = managed.filter_map { |assignment| pending_change(assignment, assigner, engine_names) }
    return if pending.empty?

    warn_mass_change(pending, managed)
    scheduled = schedule(pending.first(MAX_CHANGES), assigner)
    Rails.logger.info("[whatsapp_proxy] reconciliação: pendentes=#{pending.size} agendadas=#{scheduled} limite=#{MAX_CHANGES}")
  rescue Webshare::Client::Error, Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] reconciliação interrompida: #{e.class}")
  end

  private

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
  def pending_change(assignment, assigner, engine_names)
    return unless engine_names.include?(assignment.session_name)

    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    return [assignment, owner, :plan] if assignment.migratable_to?(owner)

    listed = WhatsappProxy::Assigner.listed(assigner.pool(assignment.pool), assignment)
    return [assignment, owner, :gone] if listed.nil?

    [assignment, owner, :credential] if listed.credential_digest != assignment.credential_digest
  end

  def schedule(batch, assigner)
    batch.each_with_index.count do |(assignment, owner, _reason), index|
      next false if assigner.resolve(assignment.session_name, owner, assigner.pool(owner.pool)).nil?

      WhatsappProxy::ApplyJob.set(wait: index * SPACING).perform_later(assignment.session_name)
      true
    end
  end

  def warn_mass_change(pending, managed)
    gone = pending.count { |(_assignment, _owner, reason)| reason == :gone }
    return unless gone * 2 > managed.size

    Rails.logger.error("[whatsapp_proxy] #{gone} de #{managed.size} IPs atribuídos sumiram da lista da Webshare " \
                       "(troca em massa?). Trocando no máximo #{MAX_CHANGES} por rodada.")
  end
end
