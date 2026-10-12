# What Meta needs in a template's structure before we ask it to create or edit one (#1380, épico #1320). Checked by the
# `Manager` before any call to the Graph: a template that breaks it is refused here (422 with the code), not by Meta
# days later. The screen applies the same rule before sending (helpers/regraEstrutural.js + conferência); the
# templates the gallery offers are proven against both in spec/fixtures/whatsapp_templates/prontos.json.
#
# Read from `components` (Meta's schema), never from the text. Codes, in the order they are found:
#   marketing_only      — COPY_CODE (coupon), catalog buttons, carousel or limited-time offer outside MARKETING;
#   media_required      — IMAGE, VIDEO or DOCUMENT header without the file handle;
#   button_order        — quick replies split by other buttons (Meta wants them in one group);
#   button_text_missing — QUICK_REPLY, URL or PHONE_NUMBER without text;
#   button_text_long    — button text over 25 characters;
#   url_missing         — URL button without the address;
#   url_example         — URL ending in a variable without the example;
#   phone_missing       — PHONE_NUMBER button without the number;
#   copy_code_example   — COPY_CODE without an example code of 1 to 15 letters and digits;
#   carousel_cards      — carousel without 2 to 10 cards;
#   carousel_card       — a card without a media header, body text or buttons;
#   offer_title         — limited-time offer without a title of 1 to 16 characters;
#   offer_buttons       — limited-time offer without its URL button, or with a countdown and no COPY_CODE button.
# Sendability in a campaign is a different rule (`SendableFormat`); helpers are shared from it.
module Whatsapp::Templates::SubmitFormat
  MARKETING = 'MARKETING'.freeze
  MARKETING_ONLY_COMPONENTS = %w[CAROUSEL LIMITED_TIME_OFFER].freeze
  MARKETING_ONLY_BUTTONS = %w[COPY_CODE CATALOG MPM SPM].freeze
  TEXT_BUTTONS = %w[QUICK_REPLY URL PHONE_NUMBER].freeze
  MEDIA_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  BUTTON_TEXT_MAX = 25
  CODE_MAX = 15
  OFFER_TITLE_MAX = 16
  CARDS = (2..10)
  CODE_CHARACTERS = [*'a'..'z', *'A'..'Z', *'0'..'9'].to_set.freeze

  module_function

  # Codes of everything wrong, without repeats (empty: Meta can receive it).
  def problems(template)
    template = template.is_a?(Hash) ? template.stringify_keys : {}
    components = Whatsapp::Templates::SendableFormat.hashes(template['components'])
    category = upcase(template['category'])
    found = []
    found << 'marketing_only' if category != MARKETING && marketing_only?(components)
    found << 'media_required' unless media_handle?(component(components, 'HEADER'))
    found.concat(button_problems(buttons_of(components)))
    found.concat(carousel_problems(component(components, 'CAROUSEL')))
    found.concat(offer_problems(component(components, 'LIMITED_TIME_OFFER'), buttons_of(components)))
    found.uniq
  end

  # The create request carries the example as a string; a template read back from Meta may carry it in a list.
  def valid_code?(example)
    code = (example.is_a?(Array) ? example.first : example).to_s
    code.length.between?(1, CODE_MAX) && code.each_char.all? { |char| CODE_CHARACTERS.include?(char) }
  end

  def marketing_only?(components)
    components.any? { |item| MARKETING_ONLY_COMPONENTS.include?(upcase(item['type'])) } ||
      buttons_of(components).any? { |button| MARKETING_ONLY_BUTTONS.include?(upcase(button['type'])) }
  end

  TEXT_CHECKS = [['button_text_missing', ->(button) { filled?(button['text']) }],
                 ['button_text_long', ->(button) { button['text'].to_s.strip.length <= BUTTON_TEXT_MAX }]].freeze
  # Each button type and what it cannot lack: [code, ok?].
  BUTTON_CHECKS = {
    'QUICK_REPLY' => TEXT_CHECKS,
    'URL' => TEXT_CHECKS + [['url_missing', ->(button) { filled?(button['url']) }],
                            ['url_example', ->(button) { url_example?(button) }]],
    'PHONE_NUMBER' => TEXT_CHECKS + [['phone_missing', ->(button) { filled?(button['phone_number']) }]],
    'COPY_CODE' => [['copy_code_example', ->(button) { valid_code?(button['example']) }]]
  }.freeze

  def button_problems(buttons)
    found = buttons.flat_map do |button|
      BUTTON_CHECKS.fetch(upcase(button['type']), []).reject { |_code, ok| ok.call(button) }.map(&:first)
    end
    quick_replies_grouped?(buttons) ? found : ['button_order', *found]
  end

  # Quick replies all together, before or after the other buttons: at most one switch between the two kinds.
  def quick_replies_grouped?(buttons)
    kinds = buttons.map { |button| upcase(button['type']) == 'QUICK_REPLY' }
    kinds.each_cons(2).count { |current, following| current != following } <= 1
  end

  # A URL with a variable at the end ({{1}}) goes with an example of that end.
  def url_example?(button)
    return true unless button['url'].to_s.include?('{{')

    Array(button['example']).any? { |value| filled?(value) }
  end

  def media_handle?(header)
    return true unless header && MEDIA_FORMATS.include?(upcase(header['format']))

    Array(header.dig('example', 'header_handle')).any? { |handle| filled?(handle) }
  end

  def carousel_problems(carousel)
    return [] unless carousel

    cards = Whatsapp::Templates::SendableFormat.hashes(carousel['cards'])
    return ['carousel_cards'] unless CARDS.cover?(cards.size)

    cards.flat_map { |card| card_problems(Whatsapp::Templates::SendableFormat.hashes(card['components'])) }
  end

  def card_problems(parts)
    header = component(parts, 'HEADER')
    complete = header && Array(header.dig('example', 'header_handle')).any?(&:present?) &&
               !blank?(component(parts, 'BODY')&.dig('text')) && buttons_of(parts).any?
    complete ? button_problems(buttons_of(parts)) : ['carousel_card']
  end

  def offer_problems(offer, buttons)
    return [] unless offer

    details = offer['limited_time_offer'].is_a?(Hash) ? offer['limited_time_offer'] : {}
    found = []
    found << 'offer_title' unless details['text'].to_s.strip.length.between?(1, OFFER_TITLE_MAX)
    found << 'offer_buttons' unless offer_buttons?(details, buttons.map { |button| upcase(button['type']) })
    found
  end

  # The offer always links somewhere; with the countdown, Meta also asks for the coupon button.
  def offer_buttons?(details, types)
    types.include?('URL') && (!details['has_expiration'] || types.include?('COPY_CODE'))
  end

  def buttons_of(components)
    Whatsapp::Templates::SendableFormat.hashes(component(components, 'BUTTONS')&.dig('buttons'))
  end

  def component(components, type)
    components.find { |item| upcase(item['type']) == type }
  end

  def blank?(value)
    value.to_s.strip.empty?
  end

  def filled?(value)
    !blank?(value)
  end

  def upcase(value)
    Whatsapp::Templates::SendableFormat.upcase(value)
  end
end
