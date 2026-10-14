# A Webshare troca IP morto e pode renovar a lista inteira (#1516): o motor ficaria apontando para um IP que não existe
# mais. A cada rodada busca cada plano UMA vez e, para cada sessão cujo IP saiu da lista (ou da fatia), ficou inválido,
# mudou de credencial, é de outro plano (o número trocou de tipo: WAHA ↔ Híbrido) ou de outra conta, atribui de novo e
# agenda a troca no motor. No máximo MAX_CHANGES por rodada, espaçadas, para nunca reiniciar todos os números de uma vez.
class WhatsappProxy::ReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_CHANGES = 5
  SPACING = 2.minutes

  def perform
    assigner = WhatsappProxy::Assigner.new
    return unless assigner.enabled?

    managed = WhatsappProxy::Assignment.where.not(webshare_proxy_id: nil).order(:assigned_at).to_a
    pending = managed.filter_map { |assignment| pending_change(assignment, assigner) }
    return if pending.empty?

    warn_mass_change(pending, managed)
    scheduled = schedule(pending.first(MAX_CHANGES), assigner)
    Rails.logger.info("[whatsapp_proxy] reconciliação: pendentes=#{pending.size} agendadas=#{scheduled} limite=#{MAX_CHANGES}")
  rescue Webshare::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] reconciliação sem lista da Webshare: #{e.message}")
  end

  private

  # [assignment, dono, motivo] quando a sessão precisa trocar; nil quando está certa (ou não tem caixa nesta stack).
  def pending_change(assignment, assigner)
    owner = WhatsappProxy::SessionOwner.find(assignment.session_name)
    return if owner.nil?
    return [assignment, owner, :plan] if assignment.pool != owner.pool || assignment.account_id != owner.account_id

    listed = WhatsappProxy::Assigner.listed(assigner.pool(owner.pool), assignment)
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
