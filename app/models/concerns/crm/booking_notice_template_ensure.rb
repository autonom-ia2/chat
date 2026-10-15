# Disparo de produto dos modelos v2 dos avisos (#1524, épico #1585): a página nova fica PUBLICADA (nasce publicada ou
# passa a publicada) ou, já publicada, troca a caixa de avisos. Com a caixa oficial Cloud e o Aviso de serviço ligado
# pelo dono (`WhatsappTemplateConsent.ativo?`), enfileira o `Crm::BookingV2::NoticeTemplateEnsureJob` só para essa
# caixa. Sem consulta à Meta aqui: o job cria fora da requisição.
#
# No modelo (depois do commit) e não no controller: publicar e trocar a caixa chegam por ações diferentes (`publish`,
# `update`) e por outros caminhos que gravam a página; aqui todos passam pelo mesmo ponto. Erro ao enfileirar não
# desfaz o que foi gravado: fica no log (só a classe) e no tracker.
module Crm::BookingNoticeTemplateEnsure
  extend ActiveSupport::Concern

  included do
    after_commit :ensure_notice_templates_later, on: [:create, :update], if: :notice_templates_trigger?
  end

  private

  def notice_templates_trigger?
    return false unless new_page? && enabled? && notice_inbox_id.present?

    previously_new_record? || saved_change_to_enabled? || saved_change_to_notice_inbox_id?
  end

  def ensure_notice_templates_later
    return unless notices_usable? && Whatsapp::Templates::MetaClient.supported?(notice_inbox)
    return unless WhatsappTemplateConsent.ativo?(account, :utility)

    Crm::BookingV2::NoticeTemplateEnsureJob.perform_later(account_id, notice_inbox_id)
  rescue StandardError => e
    Rails.logger.error("[crm][booking_v2][notice_template_ensure] nao_enfileirado page_id=#{id} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
