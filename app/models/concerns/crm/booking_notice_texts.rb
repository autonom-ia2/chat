# Texto próprio de cada aviso da página de agendamento (#1354), escrito pelo dono ou com a IA:
# `metadata['notice_texts'] = { "<aviso>" => "Oi, {{cliente.primeiro_nome}}! ... {{horario.data_hora}} ... {{horario.link_gestao}}" }`.
#
# Fica em `metadata`, não em `notice_templates`: `notice_templates` é o modelo aprovado de cada aviso (Meta ou canal
# API), com formato fechado e lido pelo `Notices::Route` para decidir o envio; o texto livre é outra coisa e não pode
# virar "modelo" por engano. Sem migration. Texto vazio = volta ao texto padrão (a chave sai). A conferência
# (`Notices::CustomText.problem`) roda só quando os textos mudam; o envio confere de novo.
module Crm::BookingNoticeTexts
  extend ActiveSupport::Concern

  NOTICE_TEXTS_KEY = 'notice_texts'.freeze

  included do
    validate :notice_texts_must_be_valid
  end

  def notice_texts
    texts = metadata.to_h[NOTICE_TEXTS_KEY]
    texts.is_a?(Hash) ? texts : {}
  end

  def notice_text(kind)
    notice_texts[kind.to_s].presence
  end

  def notice_texts=(value)
    self.metadata = metadata.to_h.merge(NOTICE_TEXTS_KEY => value.is_a?(Hash) ? normalized_notice_texts(value) : value)
  end

  private

  def normalized_notice_texts(value)
    value.to_h.stringify_keys.transform_values { |text| text.is_a?(String) ? text.strip : text }.compact_blank
  end

  def notice_texts_must_be_valid
    raw = metadata.to_h[NOTICE_TEXTS_KEY]
    return if raw.nil? || raw == attribute_in_database(:metadata).to_h[NOTICE_TEXTS_KEY]
    return errors.add(:notice_texts, 'must be an object') unless raw.is_a?(Hash)
    return errors.add(:notice_texts, 'unknown notice') unless (raw.keys - Crm::MeetingNotice::KINDS).empty?

    raw.each { |kind, text| add_notice_text_error(kind, text) }
  end

  def add_notice_text_error(kind, text)
    custom = Crm::BookingV2::Notices::CustomText
    problem = text.is_a?(String) ? custom.problem(text) : :blank
    errors.add(:notice_texts, custom.message(problem, kind: kind, locale: notice_texts_locale)) if problem
  end

  def notice_texts_locale
    Crm::BookingV2::Notices::Text.locale(account)
  end
end
