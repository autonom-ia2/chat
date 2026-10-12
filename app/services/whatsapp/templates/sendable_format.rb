# The single rule of "which WhatsApp template format our engines can send today" (#1329, épico #1320).
# Read from the structure of `components` (Meta's schema), never from the text of the template.
#
# Sendable: BODY, FOOTER, a HEADER of TEXT, IMAGE, VIDEO or DOCUMENT, and buttons QUICK_REPLY, URL
# (fixed or with a variable suffix) and PHONE_NUMBER. Sendable with a warning (works today, kept):
#   flow_without_token — FLOW button, sent without flow_token;
#   unknown_button     — a button type this rule does not know yet, sent as today (no parameter).
# A COPY_CODE button is sendable only when the send carries its code (`coupon_codes:` = the button
# indexes whose code was recorded, as the legacy campaign dialog does); the journey does not ask for it.
# Not sendable yet, each with its reason code:
#   copy_code, carousel, limited_time_offer, catalog (CATALOG/MPM/SPM, LIST, PRODUCT),
#   verification_code (OTP buttons), location_header, call_permission_request,
#   unsupported_header, unsupported_component (a component type Meta adds later), no_components.
#
# Public for every consumer (campaign dispatch now; Route.fillable_template? of the booking notices,
# the follow-up template filter and the conversation picker in later PRs):
#   Whatsapp::Templates::SendableFormat.check(template)       # => Result(reason_code, warnings), #sendable?
#   Whatsapp::Templates::SendableFormat.sendable?(template)   # => true/false
#
# Category rules stay in Whatsapp::AuthenticationTemplateGuard (authentication template to a BSUID
# recipient); this rule only looks at the format, so the two never repeat each other.
module Whatsapp::Templates::SendableFormat
  Result = Data.define(:reason_code, :warnings) do
    def sendable?
      reason_code.nil?
    end
  end

  SENDABLE_HEADER_FORMATS = %w[TEXT IMAGE VIDEO DOCUMENT].freeze
  SENDABLE_BUTTONS = %w[QUICK_REPLY URL PHONE_NUMBER FLOW].freeze
  COMPONENT_REASONS = {
    'CAROUSEL' => 'carousel', 'LIMITED_TIME_OFFER' => 'limited_time_offer', 'CATALOG' => 'catalog',
    'LIST' => 'catalog', 'PRODUCT' => 'catalog', 'CALL_PERMISSION_REQUEST' => 'call_permission_request'
  }.freeze
  HEADER_REASONS = { 'LOCATION' => 'location_header', 'PRODUCT' => 'catalog' }.freeze
  BUTTON_REASONS = {
    'COPY_CODE' => 'copy_code', 'OTP' => 'verification_code', 'CATALOG' => 'catalog', 'MPM' => 'catalog', 'SPM' => 'catalog'
  }.freeze
  FLOW_WITHOUT_TOKEN = 'flow_without_token'.freeze
  UNKNOWN_BUTTON = 'unknown_button'.freeze
  NO_COMPONENTS = 'no_components'.freeze

  module_function

  def sendable?(template, coupon_codes: [])
    check(template, coupon_codes: coupon_codes).sendable?
  end

  def check(template, coupon_codes: [])
    components = hashes(template.is_a?(Hash) ? template['components'] : nil)
    return Result.new(reason_code: NO_COMPONENTS, warnings: []) if components.empty?

    reason = components.lazy.filter_map { |component| component_reason(component, coupon_codes) }.first
    Result.new(reason_code: reason, warnings: warnings(components))
  end

  def component_reason(component, coupon_codes)
    type = upcase(component['type'])
    case type
    when 'BODY', 'FOOTER' then nil
    when 'HEADER' then header_reason(component)
    when 'BUTTONS' then buttons_reason(component, coupon_codes)
    else COMPONENT_REASONS.fetch(type, 'unsupported_component')
    end
  end

  def header_reason(header)
    format = upcase(header['format'])
    return if format.empty? || SENDABLE_HEADER_FORMATS.include?(format)

    HEADER_REASONS.fetch(format, 'unsupported_header')
  end

  def buttons_reason(component, coupon_codes)
    Array(component['buttons']).each_with_index.lazy.filter_map do |button, index|
      next unless button.is_a?(Hash)

      type = upcase(button['type'])
      next if type == 'COPY_CODE' && coupon_codes.include?(index)

      BUTTON_REASONS[type]
    end.first
  end

  def warnings(components)
    types = button_types(components)
    result = []
    result << FLOW_WITHOUT_TOKEN if types.include?('FLOW')
    result << UNKNOWN_BUTTON if types.any? { |type| unknown_button?(type) }
    result
  end

  def button_types(components)
    components.select { |component| upcase(component['type']) == 'BUTTONS' }
              .flat_map { |component| hashes(component['buttons']) }.map { |button| upcase(button['type']) }
  end

  def unknown_button?(type)
    SENDABLE_BUTTONS.exclude?(type) && !BUTTON_REASONS.key?(type)
  end

  def hashes(list)
    Array(list).select { |item| item.is_a?(Hash) }
  end

  def upcase(value)
    value.to_s.upcase
  end
end
