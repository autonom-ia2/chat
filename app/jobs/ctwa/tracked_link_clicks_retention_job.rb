# Retenção do dado pessoal dos cliques de página (#1011, LGPD: minimização).
#
# O clique guarda o formulário que o cliente digitou (lead_data) e, com consentimento, os
# sinais da Meta (fbc, fbp, IP, user agent). A linha do clique continua (conta na tabela
# de campanhas); só o dado pessoal some:
# - clique que expirou sem virar conversa: não tem mais finalidade nenhuma;
# - clique atribuído: o formulário já foi copiado para a conversa e os sinais só servem
#   para o envio à Meta; somem depois de ATTRIBUTED_RETENTION.
class Ctwa::TrackedLinkClicksRetentionJob < ApplicationJob
  queue_as :scheduled_jobs

  # A venda pode fechar semanas depois do clique, e o evento da Meta precisa dos sinais.
  ATTRIBUTED_RETENTION = 28.days
  RESET = Ctwa::TrackedLinkClick::PERSONAL_DATA_RESET

  def perform
    expired_unattributed.in_batches.update_all(RESET) # rubocop:disable Rails/SkipsModelValidations
    old_attributed.in_batches.update_all(RESET) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def with_personal_data
    Ctwa::TrackedLinkClick.where.not(lead_data: {}).or(Ctwa::TrackedLinkClick.where.not(meta_signals: {}))
                          .or(Ctwa::TrackedLinkClick.where.not(user_agent: nil))
  end

  def expired_unattributed
    with_personal_data.where(conversation_id: nil).where('expires_at <= ?', Time.current)
  end

  def old_attributed
    with_personal_data.where.not(conversation_id: nil).where('created_at <= ?', ATTRIBUTED_RETENTION.ago)
  end
end
