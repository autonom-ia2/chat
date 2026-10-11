# Modelos de aviso do WhatsApp oficial na página de agendamento (#1272), ações do BookingPagesController: a sugestão
# da IA e o estado dos pedidos (quem configura páginas) e a criação na Meta (só administrador, só no clique, num job). A
# caixa vem do escopo de caixas que a própria pessoa enxerga (`Crm::BookingPageInboxes#notice_inboxes`).
module Crm::BookingPageNoticeTemplates
  extend ActiveSupport::Concern

  private

  # A IA sugere, entre os aprovados da caixa que o envio aceita, o modelo de cada aviso. Sem IA (desligada, sem chave ou
  # com erro), `ai_failed` e a tela segue com a escolha à mão. `can_create`: o botão de criar (só administrador, só Cloud).
  def render_notice_template_suggestions
    inbox = official_notice_inbox
    return render_unprocessable('crm.booking_v2.notice_inbox_invalid') if inbox.blank?

    suggestions, failed = suggest_notice_templates(inbox)
    render json: { payload: { suggestions: suggestions, ai_failed: failed, can_create: can_create_notice_templates?(inbox),
                              requests: notice_requests(inbox).states } }
  end

  # O estado de cada pedido, para a tela acompanhar o "Enviando para a Meta…" sem recarregar.
  def render_notice_template_requests
    inbox = official_notice_inbox
    return render_unprocessable('crm.booking_v2.notice_inbox_invalid') if inbox.blank?

    render json: { payload: { requests: notice_requests(inbox).states } }
  end

  # "Criar os modelos na Meta": escreve na conta do WhatsApp do cliente, por isso só administrador
  # (`BookingPagePolicy#create_notice_templates?`) e só no clique. Responde na hora; o job cria. Com envio em andamento
  # nesta página e caixa, não enfileira outro.
  def render_created_notice_templates
    inbox = official_notice_inbox
    return render_unprocessable('crm.booking_v2.notice_inbox_invalid') if inbox.blank?
    return render_unprocessable('crm.booking_v2.notice_templates_unsupported') unless ::Crm::BookingV2::NoticeTemplates::Creator.supported?(inbox)

    requests = notice_requests(inbox)
    kinds = requests.start!(params[:kinds])
    ::Crm::BookingV2::NoticeTemplatesJob.perform_later(@page.id, inbox.id, kinds) if kinds.any?
    render json: { payload: { requests: requests.states, queued: kinds.any? } }, status: :accepted
  end

  def notice_requests(inbox)
    ::Crm::BookingV2::NoticeTemplates::Requests.new(page: @page, inbox: inbox)
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

  def can_create_notice_templates?(inbox)
    administrator? && ::Crm::BookingV2::NoticeTemplates::Creator.supported?(inbox)
  end
end
