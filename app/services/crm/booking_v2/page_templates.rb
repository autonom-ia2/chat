# Modelos de página de agendamento (#1187, J3-A8). Escolher um modelo já preenche nome, duração, local e horários;
# `blank` começa do zero (sem local: a publicação pede um). Título e descrição vêm do catálogo do fork
# (`config/locales/booking_v2.*.yml`), no idioma da conta.
class Crm::BookingV2::PageTemplates
  WEEKDAYS = [1, 2, 3, 4, 5].freeze
  BUSINESS_HOURS = { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => WEEKDAYS }.freeze
  BASE = { buffer_minutes: 10, min_notice_minutes: 120, booking_window_days: 14, working_hours: BUSINESS_HOURS }.freeze

  TEMPLATES = {
    'sales_30' => BASE.merge(duration_minutes: 30, locations: [{ 'type' => 'whatsapp_video' }]),
    'consult_45' => BASE.merge(duration_minutes: 45, locations: [{ 'type' => 'in_person' }]),
    'visit_60' => BASE.merge(duration_minutes: 60, locations: [{ 'type' => 'in_person' }]),
    'blank' => { duration_minutes: 30, buffer_minutes: 0, min_notice_minutes: 0, booking_window_days: 14,
                 working_hours: BUSINESS_HOURS, locations: [] }
  }.freeze

  class UnknownTemplate < ArgumentError; end

  def self.keys
    TEMPLATES.keys
  end

  # Atributos para `Crm::AgentBookingProfile.new`, sem conta, responsável nem funil (quem cria decide).
  def self.attributes_for(key, locale: I18n.default_locale)
    preset = TEMPLATES[key.to_s]
    raise UnknownTemplate, "unknown booking page template: #{key}" if preset.nil?

    preset.deep_dup.merge(
      template_key: key.to_s,
      title: text(key, 'title', locale),
      description: text(key, 'description', locale)
    )
  end

  def self.text(key, field, locale)
    path = "crm.booking_v2.templates.#{key}.#{field}"
    I18n.t(path, locale: locale, default: I18n.t(path, locale: :en))
  end
  private_class_method :text
end
