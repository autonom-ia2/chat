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
#   url_invalid         — URL that is not a full http(s) address with a domain;
#   phone_invalid       — phone without "+" and the country code (8 to 15 digits);
#   url_example         — URL ending in a variable without the example;
#   stray_braces        — {{ or }} typed in the footer, a button text or the offer title (only the body has variables);
#   phone_missing       — PHONE_NUMBER button without the number;
#   copy_code_example   — COPY_CODE without an example code of 1 to 15 letters and digits;
#   carousel_cards      — carousel without 2 to 10 cards;
#   carousel_media      — cards with different media (a photo in one, a video in another);
#   carousel_card       — a card without a media header, body text or buttons;
#   offer_title         — limited-time offer without a title of 1 to 16 characters;
#   offer_buttons       — limited-time offer without its URL button, or with a countdown and no COPY_CODE button.
# In an edit (`edit_problems`), one more code:
#   category_change_not_allowed — the edit asks for another category. Meta refuses it (#1394: seen on a REJECTED template; the docs,
#                                 developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-management,
#                                 only say "You cannot edit the category of an approved template"), so the product never changes it.
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
  DIGITS = ('0'..'9').to_set.freeze
  URL_STARTS = %w[https:// http://].freeze

  module_function

  # What an edit cannot ask, compared with the template as it is in the inbox list (`current`).
  def edit_problems(current, content)
    content = content.is_a?(Hash) ? content.stringify_keys : {}
    return [] unless content.key?('category')

    upcase(content['category']) == upcase(current.to_h.stringify_keys['category']) ? [] : ['category_change_not_allowed']
  end

  # Codes of everything wrong, without repeats (empty: Meta can receive it).
  def problems(template)
    template = template.is_a?(Hash) ? template.stringify_keys : {}
    components = Whatsapp::Templates::SendableFormat.hashes(template['components'])
    buttons = buttons_of(components)
    (top_problems(components, upcase(template['category'])) + button_problems(buttons) +
      carousel_problems(component(components, 'CAROUSEL')) +
      offer_problems(component(components, 'LIMITED_TIME_OFFER'), buttons)).uniq
  end

  def top_problems(components, category)
    [('marketing_only' if category != MARKETING && marketing_only?(components)),
     ('media_required' unless media_handle?(component(components, 'HEADER'))),
     ('stray_braces' if stray_braces?(components))].compact
  end

  def stray_braces?(components)
    braces?(component(components, 'FOOTER')&.dig('text')) ||
      braces?(component(components, 'LIMITED_TIME_OFFER')&.dig('limited_time_offer', 'text'))
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
                 ['button_text_long', ->(button) { button['text'].to_s.length <= BUTTON_TEXT_MAX }],
                 ['stray_braces', ->(button) { !braces?(button['text']) }]].freeze
  # Each button type and what it cannot lack: [code, ok?].
  BUTTON_CHECKS = {
    'QUICK_REPLY' => TEXT_CHECKS,
    'URL' => TEXT_CHECKS + [['url_missing', ->(button) { filled?(button['url']) }],
                            ['url_invalid', ->(button) { blank?(button['url']) || url?(button['url']) }],
                            ['url_example', ->(button) { url_example?(button) }]],
    'PHONE_NUMBER' => TEXT_CHECKS + [['phone_missing', ->(button) { filled?(button['phone_number']) }],
                                     ['phone_invalid', ->(button) { blank?(button['phone_number']) || phone?(button['phone_number']) }]],
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

  # Starts with http(s)://, printable ASCII without spaces (the screen's rule too) and a host with a dot; a variable
  # ending ({{1}}) is left out of the reading.
  def url?(url)
    base = url.to_s.split('{{').first.to_s
    return false unless URL_STARTS.any? { |start| base.start_with?(start) }
    return false unless base.each_char.all? { |char| char.ord.between?(33, 126) }

    URI.parse(base).host.to_s.include?('.')
  rescue URI::InvalidURIError
    false
  end

  # Country code first: "+" and 8 to 15 digits (what the screen sends).
  def phone?(phone)
    digits = phone.to_s.delete_prefix('+')
    phone.to_s.start_with?('+') && digits.length.between?(8, 15) && digits.each_char.all? { |char| DIGITS.include?(char) }
  end

  # A URL with a variable at the end ({{1}}) goes with an example of that end.
  def url_example?(button)
    return true unless button['url'].to_s.include?('{{')

    Array(button['example']).any? { |value| filled?(value) }
  end

  def braces?(text)
    text.to_s.include?('{{') || text.to_s.include?('}}')
  end

  def media_handle?(header)
    return true unless header && MEDIA_FORMATS.include?(upcase(header['format']))

    Array(header.dig('example', 'header_handle')).any? { |handle| filled?(handle) }
  end

  def carousel_problems(carousel)
    return [] unless carousel

    cards = Whatsapp::Templates::SendableFormat.hashes(carousel['cards'])
    return ['carousel_cards'] unless CARDS.cover?(cards.size)
    return ['carousel_media'] if cards.map { |card| card_media(card) }.reject(&:empty?).uniq.size > 1

    cards.flat_map { |card| card_problems(Whatsapp::Templates::SendableFormat.hashes(card['components'])) }
  end

  def card_media(card)
    upcase(component(Whatsapp::Templates::SendableFormat.hashes(card['components']), 'HEADER')&.dig('format'))
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
