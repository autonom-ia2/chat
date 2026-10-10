# Nome leigo do local da reunião (#1189) para a página pública e o arquivo de calendário: o rótulo que o dono da
# página escreveu ou, sem ele, o texto do catálogo do fork no idioma da conta ("Vídeo no WhatsApp", "Presencial").
class Crm::BookingV2::LocationLabel
  def self.for(location, account:)
    data = location.to_h
    return data['label'] if data['label'].present?
    return unless Crm::BookingPageSettings::LOCATION_TYPES.include?(data['type'])

    I18n.t("crm.booking_v2.locations.#{data['type']}", locale: locale(account))
  end

  def self.locale(account)
    raw = account&.locale.to_s
    I18n.available_locales.map(&:to_s).include?(raw) ? raw : I18n.default_locale
  end
end
