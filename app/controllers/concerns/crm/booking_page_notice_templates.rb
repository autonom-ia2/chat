# Modelos de aviso do WhatsApp oficial na página de agendamento (#1272), ação do BookingPagesController: a IA sugere,
# entre os aprovados da caixa, o modelo de cada aviso (quem configura páginas). A caixa vem do escopo de caixas que a
# própria pessoa enxerga (`Crm::BookingPageInboxes#notice_inboxes`).
#
# O botão "Criar os modelos na Meta" (v1) saiu em #1612: ele postava na Meta sem o `Whatsapp::Templates::Garantir` e
# sem a autorização do dono (#1585). Os modelos dos avisos agora são os v2, criados pelo
# `Crm::BookingV2::NoticeTemplateEnsureJob` só com o Aviso de serviço ligado.
module Crm::BookingPageNoticeTemplates
  extend ActiveSupport::Concern

  private

  # Sem IA (desligada, sem chave ou com erro), `ai_failed` e a tela segue com a escolha à mão.
  def render_notice_template_suggestions
    inbox = official_notice_inbox
    return render_unprocessable('crm.booking_v2.notice_inbox_invalid') if inbox.blank?

    suggestions, failed = suggest_notice_templates(inbox)
    render json: { payload: { suggestions: suggestions, ai_failed: failed } }
  end

  # Caixa de avisos do WhatsApp oficial, do escopo de caixas que a própria pessoa enxerga.
  def official_notice_inbox
    inbox = notice_inboxes.find(params[:inbox_id])
    inbox if ::Crm::AgentBookingProfile.notice_channel_kind(inbox) == 'whatsapp'
  end

  def suggest_notice_templates(inbox)
    kinds = params.key?(:kinds) ? Array(params[:kinds]) : ::Crm::MeetingNotice::KINDS
    [::Crm::BookingV2::NoticeTemplates::Suggester.new(account: Current.account, inbox: inbox, kinds: kinds).perform, false]
  rescue ::Crm::BookingV2::NoticeTemplates::Suggester::Unavailable => e
    Rails.logger.info("[crm][booking_v2][notice_templates] suggestion_unavailable inbox_id=#{inbox.id} reason=#{e.message}")
    [{}, true]
  end
end
