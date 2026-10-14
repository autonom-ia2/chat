# A Webshare troca IP morto e pode renovar a lista inteira (#1516): o motor ficaria apontando para um IP que não existe
# mais. A cada rodada busca a lista UMA vez e, para cada sessão cujo IP saiu da lista, ficou inválido ou mudou de
# credencial, atribui (se preciso) e agenda a troca no motor. No máximo MAX_CHANGES por rodada, espaçadas, para nunca
# reiniciar todos os números de uma vez.
class WhatsappProxy::ReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_CHANGES = 5
  SPACING = 2.minutes

  def perform
    assigner = WhatsappProxy::Assigner.new
    return unless assigner.enabled?

    proxies = Webshare::Client.new.proxies
    managed = WhatsappProxy::Assignment.where.not(webshare_proxy_id: nil).order(:assigned_at).to_a
    pending = managed.reject { |assignment| current?(assignment, proxies) }
    return if pending.empty?

    warn_mass_change(pending, managed, proxies)
    scheduled = schedule(pending.first(MAX_CHANGES), assigner, proxies)
    Rails.logger.info("[whatsapp_proxy] reconciliação: pendentes=#{pending.size} agendadas=#{scheduled} limite=#{MAX_CHANGES}")
  rescue Webshare::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] reconciliação sem lista da Webshare: #{e.message}")
  end

  private

  def current?(assignment, proxies)
    listed = WhatsappProxy::Assigner.listed(proxies, assignment)
    listed.present? && listed.credential_digest == assignment.credential_digest
  end

  def schedule(batch, assigner, proxies)
    batch.each_with_index.count do |assignment, index|
      next false if assigner.resolve(assignment.session_name, proxies).nil?

      WhatsappProxy::ApplyJob.set(wait: index * SPACING).perform_later(assignment.session_name)
      true
    end
  end

  def warn_mass_change(pending, managed, proxies)
    gone = pending.count { |assignment| WhatsappProxy::Assigner.listed(proxies, assignment).nil? }
    return unless gone * 2 > managed.size

    Rails.logger.error("[whatsapp_proxy] #{gone} de #{managed.size} IPs atribuídos sumiram da lista da Webshare " \
                       "(troca em massa?). Trocando no máximo #{MAX_CHANGES} por rodada.")
  end
end
