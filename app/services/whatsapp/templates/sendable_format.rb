# The single rule of "which WhatsApp template format our engines can send" (#1329, #1334, épico #1320).
# Read from the structure of `components` (Meta's schema), never from the text of the template.
#
# Sendable: BODY, FOOTER, a HEADER of TEXT, IMAGE, VIDEO or DOCUMENT, and buttons QUICK_REPLY, URL
# (fixed or with a variable suffix) and PHONE_NUMBER. Sendable with a warning (works today, kept):
#   flow_without_token — FLOW button sent without flow_token (Meta's default is "unused");
#   unknown_button     — a button type this rule does not know yet, sent as today (no parameter).
# Sendable only when the send carries what Meta asks (`recorded:` = the campaign's processed_params, #1334;
# the payload is built by Whatsapp::Templates::SendComponents):
#   COPY_CODE button   — buttons[i] = { type: 'copy_code', parameter: <code> };
#   LIMITED_TIME_OFFER — with has_expiration, limited_time_offer.expiration_time_ms still ahead (offer_expired after);
#   CAROUSEL           — one card per template card, each header with media_blob (file chosen in the campaign), media_url
#                        or media_stored (the template's saved file);
#   CATALOG button     — buttons[i] = { type: 'catalog' };
#   catalog products   — one product (SPM), several (MPM) or a carousel of product cards (#1418), with the number of
#                        products Meta accepts in products.retailer_ids (Whatsapp::Templates::ProductParams);
#   URL ending in {{1}} — only with `url_suffix: true` (the conversation send, #1705): buttons[i].parameter
#                        (reason url_parameter).
# Not sendable, each with its reason code:
#   verification_code (OTP: a one-time code is asked by one person in an app, never sent to a list),
#   catalog (MPM/SPM or product cards without the chosen products; LIST, PRODUCT), location_header,
#   call_permission_request, unsupported_header, unsupported_component (a component type Meta adds later), no_components.
#
# Public for every consumer (campaign dispatch now; Route.fillable_template? of the booking notices,
# the follow-up template filter and the conversation picker in later PRs):
#   Whatsapp::Templates::SendableFormat.check(template, recorded: {})  # => Result(reason_code, warnings), #sendable?
#   Whatsapp::Templates::SendableFormat.sendable?(template)            # => true/false
#   Whatsapp::Templates::SendableFormat.offer_format?(template)        # => coupon, limited-time offer or carousel (#1456)
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
    'LIST' => 'catalog', 'PRODUCT' => 'catalog', 'CALL_PERMISSION_REQUEST' => 'call_permission_request'
  }.freeze
  HEADER_REASONS = { 'LOCATION' => 'location_header', 'PRODUCT' => 'catalog' }.freeze
  BUTTON_REASONS = {
    'COPY_CODE' => 'copy_code', 'OTP' => 'verification_code', 'CATALOG' => 'catalog', 'MPM' => 'catalog', 'SPM' => 'catalog'
  }.freeze
  # Button types the send fills from `recorded` (the button at the same index, with this type and this key).
  RECORDED_BUTTONS = { 'COPY_CODE' => %w[copy_code parameter], 'CATALOG' => %w[catalog type] }.freeze
  FLOW_WITHOUT_TOKEN = 'flow_without_token'.freeze
  UNKNOWN_BUTTON = 'unknown_button'.freeze
  NO_COMPONENTS = 'no_components'.freeze
  OFFER_EXPIRED = 'offer_expired'.freeze
  COUPON_MAX = 15
  # What only reaches the person inside the full template (#1456): the coupon button, the offer and the carousel.
  OFFER_COMPONENTS = %w[LIMITED_TIME_OFFER CAROUSEL].freeze
  OFFER_BUTTON = 'COPY_CODE'.freeze

  module_function

  def sendable?(template, recorded: {})
    check(template, recorded: recorded).sendable?
  end

  # The campaign free text (#1335) never replaces these: whoever got the text would lose the offer (#1456).
  def offer_format?(template)
    return true if Whatsapp::Templates::ProductParams.kind(template)

    components = hashes(template.is_a?(Hash) ? template['components'] : nil)
    components.any? { |component| OFFER_COMPONENTS.include?(upcase(component['type'])) } ||
      button_types(components).include?(OFFER_BUTTON)
  end

  def check(template, recorded: {}, now: Time.current, url_suffix: false)
    components = hashes(template.is_a?(Hash) ? template['components'] : nil)
    return Result.new(reason_code: NO_COMPONENTS, warnings: []) if components.empty?

    recorded = recorded.is_a?(Hash) ? recorded : {}
    return products_result(template, components, recorded) if Whatsapp::Templates::ProductParams.kind(template)

    reason = components_reason(components, recorded, now, url_suffix)
    Result.new(reason_code: reason, warnings: warnings(components, recorded))
  end

  def components_reason(components, recorded, now, url_suffix)
    reason = components.lazy.filter_map { |component| component_reason(component, recorded, now) }.first
    return reason if reason || !url_suffix

    Whatsapp::Templates::UrlSuffix.reason(components, recorded)
  end

  # #1418: the products decide; the rest of the template (body, text header, footer) is checked as usual.
  def products_result(template, components, recorded)
    reason = 'catalog' unless Whatsapp::Templates::ProductParams.ready?(template, recorded)
    reason ||= components.lazy.filter_map { |component| product_template_reason(component) }.first
    Result.new(reason_code: reason, warnings: [])
  end

  def product_template_reason(component)
    type = upcase(component['type'])
    return if %w[BODY FOOTER BUTTONS CAROUSEL].include?(type)
    return if type == 'HEADER' && %w[PRODUCT TEXT].include?(upcase(component['format']))

    type == 'HEADER' ? 'unsupported_header' : COMPONENT_REASONS.fetch(type, 'unsupported_component')
  end

  def component_reason(component, recorded, now)
    type = upcase(component['type'])
    case type
    when 'BODY', 'FOOTER' then nil
    when 'HEADER' then header_reason(component)
    when 'BUTTONS' then buttons_reason(component, recorded)
    when 'LIMITED_TIME_OFFER' then offer_reason(component, recorded, now)
    when 'CAROUSEL' then carousel_reason(component, recorded)
    else COMPONENT_REASONS.fetch(type, 'unsupported_component')
    end
  end

  def header_reason(header)
    format = upcase(header['format'])
    return if format.empty? || SENDABLE_HEADER_FORMATS.include?(format)

    HEADER_REASONS.fetch(format, 'unsupported_header')
  end

  def buttons_reason(component, recorded)
    sent = Array(recorded['buttons'])
    Array(component['buttons']).each_with_index.lazy.filter_map do |button, index|
      next unless button.is_a?(Hash)

      type = upcase(button['type'])
      next if recorded_button?(type, sent[index])

      BUTTON_REASONS[type]
    end.first
  end

  # The coupon has 1 to 15 characters: the Chatwoot send refuses more (Meta's limit for the offer code).
  def recorded_button?(type, sent)
    kind, key = RECORDED_BUTTONS[type]
    return false unless kind && sent.is_a?(Hash) && sent['type'].to_s.casecmp?(kind)
    return sent[key].to_s.strip.length.between?(1, COUPON_MAX) if type == 'COPY_CODE'

    sent[key].to_s.strip.present?
  end

  # Expiration is asked only when the template shows it (has_expiration); in milliseconds, like Meta.
  def offer_reason(component, recorded, now)
    return unless component.dig('limited_time_offer', 'has_expiration')

    offer = recorded['limited_time_offer']
    expiration = Integer(offer['expiration_time_ms'].to_s, exception: false) if offer.is_a?(Hash)
    return 'limited_time_offer' unless expiration
    return if expiration > (now.to_f * 1000).to_i

    OFFER_EXPIRED
  end

  def carousel_reason(component, recorded)
    carousel = recorded['carousel']
    cards = carousel.is_a?(Hash) ? Array(carousel['cards']) : []
    template_cards = hashes(component['cards'])
    return 'carousel' if template_cards.empty? || cards.size != template_cards.size

    ready = cards.each_with_index.all? { |card, index| card_media?(card) && card_buttons?(card, template_cards[index]) }
    'carousel' unless ready
  end

  def card_media?(card)
    header = card.is_a?(Hash) ? card['header'] : nil
    header.is_a?(Hash) && (header['media_url'].to_s.strip.present? || header['media_blob'].to_s.strip.present? ||
      header['media_stored'] == true)
  end

  # A card URL button whose address ends in a variable needs its value at send time.
  def card_buttons?(card, template_card)
    return false unless card_body?(card, template_card)

    sent = card.is_a?(Hash) ? Array(card['buttons']) : []
    card_template_buttons(template_card).each_with_index.all? do |button, index|
      next true unless upcase(button['type']) == 'URL' && CampaignJourney::TemplatePlaceholders.keys(button['url']).any?

      sent[index].is_a?(Hash) && sent[index]['parameter'].to_s.strip.present?
    end
  end

  # A card body with variables needs their values at send time.
  def card_body?(card, template_card)
    body = hashes(template_card['components']).find { |component| upcase(component['type']) == 'BODY' }
    sent = card.is_a?(Hash) && card['body'].is_a?(Hash) ? card['body'] : {}
    CampaignJourney::TemplatePlaceholders.keys(body&.dig('text')).all? { |key| sent[key].to_s.strip.present? }
  end

  def card_template_buttons(template_card)
    buttons = hashes(template_card['components']).find { |component| upcase(component['type']) == 'BUTTONS' }
    hashes(buttons&.dig('buttons'))
  end

  def warnings(components, recorded = {})
    types = button_types(components)
    result = []
    result << FLOW_WITHOUT_TOKEN if types.include?('FLOW') && !flow_token?(recorded)
    result << UNKNOWN_BUTTON if types.any? { |type| unknown_button?(type) }
    result
  end

  def flow_token?(recorded)
    Array(recorded['buttons']).any? { |button| button.is_a?(Hash) && button['type'].to_s.casecmp?('flow') && button['flow_token'].present? }
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
