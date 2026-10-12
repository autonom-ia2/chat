# O que o passo "Avisos" precisa para editar o texto próprio de cada aviso (#1354): o texto padrão de cada aviso com
# as chaves (ponto de partida e "Voltar ao texto padrão"), os campos com o rótulo leigo do catálogo, valores de
# EXEMPLO para a prévia (nunca de um cliente) e a linha de parar como o cliente vê. Tudo no idioma da conta.
class Crm::BookingV2::Notices::CustomTextSetup
  CustomText = Crm::BookingV2::Notices::CustomText
  SAMPLE_CODE = 'AB3K9QXZ'.freeze
  SAMPLE_START = [2026, 10, 14, 15, 0].freeze

  def initialize(page)
    @page = page
    @locale = Crm::BookingV2::Notices::Text.locale(page.account)
  end

  def to_h
    {
      defaults: Crm::MeetingNotice::KINDS.index_with { |kind| CustomText.default_text(kind, locale: @locale) },
      fields: CustomText::ALLOWED_KEYS.map { |key| { key: key, label: TemplateFields::Catalog.label(key, locale: @locale) } },
      required: CustomText::REQUIRED_KEYS, max_length: CustomText::MAX_LENGTH, samples: samples,
      stop_line: I18n.t('crm.booking_v2.notices.stop_line', link: "#{sample_link}#{Crm::BookingV2::Notices::Text::STOP_PARAM}", locale: @locale)
    }
  end

  private

  def samples
    {
      CustomText::NAME => I18n.t('crm.booking_v2.notice_texts.sample_name', locale: @locale),
      CustomText::WHEN => Time.utc(*SAMPLE_START).strftime(I18n.t('crm.booking_v2.notices.when_format', locale: @locale)),
      CustomText::LINK => sample_link,
      CustomText::BUSINESS => TemplateFields::AccountResolver.new(@page.account).value(CustomText::BUSINESS)
    }
  end

  def sample_link
    "#{Crm::BookingInvite.base_url}/b/#{SAMPLE_CODE}"
  end
end
