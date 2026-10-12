# "Escrever com IA" do texto de um aviso da página de agendamento (#1354), ação do BookingPagesController. Pede ao
# redator compartilhado (`Ai::Redacao::Escrever`, canal `whatsapp_texto`) até 2 opções para UM aviso e devolve só as
# que passam na mesma conferência de quem salva (`Notices::CustomText.problem`). Nada é salvo: a pessoa escolhe, edita
# e salva a página. Entra só o que a página e a conta dizem (título, duração, local, nome do negócio, idioma), nunca
# dado de cliente. Sem IA (desligada, sem chave, erro ou nenhuma opção boa): 422 com uma frase simples.
module Crm::BookingPageNoticeTexts
  extend ActiveSupport::Concern

  NOTICE_TEXT_FEATURE = 'aviso_redacao'.freeze
  NOTICE_TEXT_TONES = %w[curto simpatico formal].freeze
  NOTICE_TEXT_OPTIONS = 2
  # Texto da página que vai como contexto à IA: curto, é dado e não instrução.
  MAX_CONTEXT_TEXT = 120

  private

  def render_notice_text_suggestions
    kind = params[:kind].to_s
    return render_unprocessable('crm.booking_v2.notice_text_kind_invalid') unless ::Crm::MeetingNotice::KINDS.include?(kind)

    result = write_notice_text(kind)
    return render_notice_text_failure(result[:pergunta]) unless result[:status] == 'ok'

    options = usable_notice_text_options(result[:opcoes])
    return render_notice_text_failure(nil) if options.empty?

    render json: { payload: { options: options } }
  rescue ::Ai::Redacao::Escrever::Indisponivel => e
    Rails.logger.info("[crm][booking_v2][notice_texts] suggestion_unavailable page_id=#{@page.id} reason=#{e.message}")
    render_notice_text_failure(nil)
  end

  def write_notice_text(kind)
    custom = ::Crm::BookingV2::Notices::CustomText
    ::Ai::Redacao::Escrever.call(
      account: Current.account, feature: NOTICE_TEXT_FEATURE, canal: 'whatsapp_texto',
      proposito: "aviso de agendamento: #{::Crm::BookingV2::NoticeTemplates::Suggester::NOTICES.fetch(kind)}",
      limites: { max_chars: custom::MAX_LENGTH }, chaves: { permitidas: custom::ALLOWED_KEYS, obrigatorias: custom::REQUIRED_KEYS },
      tom: NOTICE_TEXT_TONES.include?(params[:tone].to_s) ? params[:tone].to_s : nil, opcoes: NOTICE_TEXT_OPTIONS,
      contexto: notice_text_context
    )
  end

  # O que a página e a conta dizem do atendimento. Nada do cliente.
  def notice_text_context
    locale = ::Crm::BookingV2::Notices::Text.locale(Current.account)
    {
      empresa: ::TemplateFields::AccountResolver.new(Current.account).value('minha_empresa.nome').to_s.first(MAX_CONTEXT_TEXT),
      atendimento: @page.title.to_s.first(MAX_CONTEXT_TEXT), duracao_minutos: @page.duration_minutes, idioma: locale.to_s,
      locais: Array(@page.locations).filter_map { |item| item.to_h['type'] }.uniq.map do |type|
        I18n.t("crm.booking_v2.locations.#{type}", locale: locale, default: type)
      end
    }
  end

  # A mesma conferência de quem salva (`CustomText`), além da do redator.
  def usable_notice_text_options(options)
    options.filter_map do |option|
      text = option[:texto]
      { text: text, keys: option[:chaves_usadas] } if ::Crm::BookingV2::Notices::CustomText.problem(text).nil?
    end
  end

  def render_notice_text_failure(question)
    locale = ::Crm::BookingV2::Notices::Text.locale(Current.account)
    message = question.presence || I18n.t('crm.booking_v2.notice_texts.ai_failed', locale: locale)
    render json: { error: 'crm.booking_v2.notice_text_ai_failed', message: message }, status: :unprocessable_entity
  end
end
