# Ajustes da página de agendamento NOVA (page_version 2, #1187): locais, durações, antecedência, marca, telefone
# e imagens. A página antiga não passa por aqui. Separado do modelo para ele caber no tamanho de classe do repo.
module Crm::BookingPageSettings
  extend ActiveSupport::Concern

  MAX_MIN_NOTICE = 14 * 24 * 60
  MAX_EXTRA_DURATIONS = 5
  LOCATION_TYPES = %w[whatsapp_video whatsapp_voice custom_link in_person google_meet teams].freeze
  TEMPLATE_KEYS = %w[sales_30 consult_45 visit_60 blank].freeze
  HEX_DIGITS = '0123456789abcdefABCDEF'.freeze
  # Meet e Teams só existem com a caixa do provedor conectada e com agenda.
  CALENDAR_LOCATIONS = { 'google_meet' => :google?, 'teams' => :microsoft? }.freeze
  MAX_LOCATIONS = 6
  MAX_TEXT = 500
  MAX_DESCRIPTION = 2000
  MAX_IMAGE_BYTES = 2.megabytes
  IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze

  included do
    before_validation :normalize_json_settings
    validate :new_page_settings_must_be_sane
  end

  private

  # jsonb vindo com chave símbolo só vira string depois de salvar: normaliza antes, para a validação ver o que vai
  # ser gravado.
  def normalize_json_settings
    self.brand = brand.deep_stringify_keys if brand.is_a?(Hash)
    self.locations = locations.map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : item } if locations.is_a?(Array)
    normalize_slot_durations
  end

  # Formulário manda número como texto ("60"); só converte o que é inteiro de verdade, o resto a validação recusa.
  def normalize_slot_durations
    return unless slot_durations.is_a?(Array)

    self.slot_durations = slot_durations.map { |value| Integer(value, exception: false) || value }
  end

  def new_page_settings_must_be_sane
    return unless new_page?

    validate_locations
    validate_slot_durations
    validate_min_notice
    validate_brand
    validate_contact_phone
    validate_images
    validate_description
    validate_timezone
  end

  def validate_description
    errors.add(:description, 'is too long') if description.to_s.length > MAX_DESCRIPTION
  end

  def validate_timezone
    return if timezone.blank? || ActiveSupport::TimeZone[timezone].present?

    errors.add(:timezone, 'is not a valid time zone')
  end

  # A caixa de agenda só é conferida quando o que depende dela muda (locais, caixa) ou quando a página vai ao ar.
  # Pausar uma página cuja caixa perdeu a agenda tem de funcionar: é justamente o que o admin quer fazer.
  def calendar_check_needed?
    new_record? || locations_changed? || inbox_id_changed? || (enabled_changed? && enabled?)
  end

  def validate_locations
    list = locations
    return errors.add(:locations, 'must be a list') unless list.is_a?(Array)
    return errors.add(:locations, 'has too many items') if list.size > MAX_LOCATIONS

    list.each { |location| validate_location(location) }
  end

  def validate_location(location)
    return errors.add(:locations, 'item must be an object') unless location.is_a?(Hash)
    return errors.add(:locations, 'unknown type') unless LOCATION_TYPES.include?(location['type'])
    return errors.add(:locations, 'label or address too long') if location_text_too_long?(location)
    return validate_calendar_location(location['type']) if CALENDAR_LOCATIONS.key?(location['type'])
    return if location['type'] != 'custom_link'

    errors.add(:locations, 'link must be an http or https URL') unless Crm::WebUrl.valid?(location['url'], max: MAX_TEXT)
  end

  def location_text_too_long?(location)
    %w[label address].any? { |key| location[key].to_s.length > MAX_TEXT }
  end

  def validate_calendar_location(type)
    return unless calendar_check_needed?

    channel = inbox&.channel
    connected = channel.is_a?(Channel::Email) && channel.calendar_enabled? && channel.public_send(CALENDAR_LOCATIONS[type])
    errors.add(:locations, 'calendar location requires a connected calendar mailbox') unless connected
  end

  def validate_slot_durations
    list = slot_durations
    ok = list.is_a?(Array) && list.size <= MAX_EXTRA_DURATIONS && list.all? { |value| valid_duration?(value) }
    errors.add(:slot_durations, 'invalid durations') unless ok
  end

  def valid_duration?(value)
    value.is_a?(Integer) && value.between?(self.class::MIN_DURATION, self.class::MAX_DURATION)
  end

  def validate_min_notice
    return if min_notice_minutes.to_i.between?(0, MAX_MIN_NOTICE)

    errors.add(:min_notice_minutes, 'out of range')
  end

  def validate_brand
    return errors.add(:brand, 'must be an object') unless brand.is_a?(Hash)

    color = brand['color']
    errors.add(:brand, 'invalid color') if color.present? && !hex_color?(color)
    errors.add(:brand, 'headline too long') if brand['headline'].to_s.length > MAX_TEXT
  end

  def hex_color?(value)
    value.is_a?(String) && value.length == 7 && value.start_with?('#') && value.delete_prefix('#').chars.all? { |char| HEX_DIGITS.include?(char) }
  end

  # Logo e foto vão para a página pública: só PNG, JPEG ou WebP (SVG pode carregar script) e até 2 MB.
  def validate_images
    %i[logo photo].each do |name|
      attachment = public_send(name)
      next unless attachment.attached?

      errors.add(name, 'must be a PNG, JPEG or WebP image') unless IMAGE_TYPES.include?(attachment.content_type)
      errors.add(name, 'is too large') if attachment.byte_size > MAX_IMAGE_BYTES
    end
  end

  def validate_contact_phone
    return if contact_phone.blank?
    return if contact_phone.start_with?('+') && TelephoneNumber.valid?(contact_phone)

    errors.add(:contact_phone, 'must be a valid E.164 number')
  end
end
