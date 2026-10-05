# Retenção do dado pessoal dos cliques de página (#1011, LGPD: minimização).
#
# O clique guarda o formulário que o cliente digitou (lead_data) e, com consentimento, os
# sinais da Meta (fbc, fbp, IP, user agent). A linha do clique continua (conta na tabela
# de campanhas); só o dado pessoal some:
# - clique que expirou sem virar conversa: não tem mais finalidade nenhuma;
# - clique atribuído, formulário e user agent: o formulário já foi copiado para a conversa;
#   somem ATTRIBUTED_RETENTION depois do clique;
# - clique atribuído, sinais da Meta: servem só ao envio do funil à Meta, que acontece
#   quando o card muda de etapa ou fecha, e a venda pode fechar bem depois do clique
#   (CA-3.5). Por isso o prazo segue o CARD, não o clique: os sinais ficam enquanto algum
#   card da conversa estiver aberto ou tiver fechado há menos de SIGNALS_AFTER_CLOSE; sem
#   card nessa situação, somem ATTRIBUTED_RETENTION depois do clique.
# Contrato: docs/crm/ponte-lp-atribuicao.md, seção 7.
class Ctwa::TrackedLinkClicksRetentionJob < ApplicationJob
  queue_as :scheduled_jobs

  ATTRIBUTED_RETENTION = 28.days
  # A Meta recusa evento com mais de 7 dias no envio; um dia de folga para a fila.
  SIGNALS_AFTER_CLOSE = Crm::MetaCapi::DispatchJob::WEBSITE_EVENT_MAX_AGE + 1.day
  RESET = Ctwa::TrackedLinkClick::PERSONAL_DATA_RESET

  # rubocop:disable Rails/SkipsModelValidations
  def perform
    expired_unattributed.in_batches.update_all(RESET)
    old_attributed.where.not(lead_data: {}).or(old_attributed.where.not(user_agent: nil))
                  .in_batches.update_all(lead_data: {}, user_agent: nil)
    signals_without_card_in_use.in_batches.update_all(meta_signals: {})
  end
  # rubocop:enable Rails/SkipsModelValidations

  private

  def with_personal_data
    Ctwa::TrackedLinkClick.where.not(lead_data: {}).or(Ctwa::TrackedLinkClick.where.not(meta_signals: {}))
                          .or(Ctwa::TrackedLinkClick.where.not(user_agent: nil))
  end

  def expired_unattributed
    with_personal_data.where(conversation_id: nil).where('expires_at <= ?', Time.current)
  end

  def old_attributed
    Ctwa::TrackedLinkClick.where.not(conversation_id: nil).where('created_at <= ?', ATTRIBUTED_RETENTION.ago)
  end

  def signals_without_card_in_use
    old_attributed.where.not(meta_signals: {})
                  .where.not(conversation_id: cards_in_use.where.not(conversation_id: nil).select(:conversation_id))
                  .where.not(conversation_id: Crm::CardConversation.where(card_id: cards_in_use.select(:id)).select(:conversation_id))
  end

  # Card que ainda pode mandar evento à Meta: aberto, ou ganho/perdido há pouco.
  def cards_in_use
    Crm::Card.where(status: :open).or(Crm::Card.where('closed_at > ?', SIGNALS_AFTER_CLOSE.ago))
  end
end
