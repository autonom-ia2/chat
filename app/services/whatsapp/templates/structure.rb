# The send-time shape of a WhatsApp template (#1329): which inputs a send has to fill. Compared at
# dispatch between the template as it is now and what the campaign recorded when it was created
# (template_params['processed_params'], built from the template's components by the campaign forms).
#   { body: ['1', 'nome'], header: 'media:image' | ['1'] | nil, buttons: { 0 => 'url', 2 => 'copy_code' } }
# Variables are read with CampaignJourney::TemplatePlaceholders (plain scan, no regular expressions).
module Whatsapp::Templates::Structure
  MEDIA_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  RECORDED_PARTS = %w[body header buttons].freeze
  MEDIA_PREFIX = 'media:'.freeze
  MEDIA_KEYS = %w[media_url media_type media_name].freeze

  module_function

  def of_template(template)
    { body: placeholder_keys(component(template, 'BODY')&.dig('text')), header: template_header(template),
      buttons: template_buttons(template) }
  end

  # nil when the campaign kept a legacy shape (flat { '1' => 'x' } or a positional array): there is
  # nothing reliable to compare. A campaign with no processed_params recorded nothing to fill.
  def of_processed_params(processed_params)
    params = processed_params.presence || {}
    return unless comparable?(params)

    { body: params['body'].to_h.keys.map(&:to_s).sort, header: recorded_header(params['header']),
      buttons: recorded_buttons(params['buttons']) }
  end

  def comparable?(params)
    return false unless params.is_a?(Hash)
    return false unless params.empty? || params.keys.map(&:to_s).intersect?(RECORDED_PARTS)

    params['body'].blank? || params['body'].is_a?(Hash)
  end

  # Indexes of the COPY_CODE buttons whose code the campaign recorded (legacy dialog: one code for everyone).
  def recorded_coupon_codes(processed_params)
    return [] unless processed_params.is_a?(Hash)

    Array(processed_params['buttons']).each_with_index.filter_map do |button, index|
      index if button.is_a?(Hash) && button['type'].to_s.casecmp?('copy_code') && button['parameter'].to_s.strip.present?
    end
  end

  def same?(recorded, current)
    differences(recorded, current).values.none?(&:present?)
  end

  # Differences without values: which parts changed and the variable keys added or removed.
  def differences(recorded, current)
    {
      missing_keys: (recorded[:body] - current[:body]), extra_keys: (current[:body] - recorded[:body]),
      header_changed: !same_header?(recorded[:header], current[:header]), buttons_changed: recorded[:buttons] != current[:buttons]
    }
  end

  # A recorded media header without media_type (older forms) matches any media header.
  def same_header?(recorded, current)
    return current.to_s.start_with?(MEDIA_PREFIX) if recorded == MEDIA_PREFIX

    recorded == current
  end

  def template_header(template)
    header = component(template, 'HEADER')
    return unless header

    format = header['format'].to_s.upcase
    return "#{MEDIA_PREFIX}#{format.downcase}" if MEDIA_FORMATS.include?(format)

    keys = placeholder_keys(header['text'])
    keys.presence
  end

  def template_buttons(template)
    Array(component(template, 'BUTTONS')&.dig('buttons')).each_with_index.with_object({}) do |(button, index), buttons|
      next unless button.is_a?(Hash)

      type = button['type'].to_s.upcase
      buttons[index] = 'url' if type == 'URL' && placeholder_keys(button['url']).any?
      buttons[index] = 'copy_code' if type == 'COPY_CODE'
    end
  end

  def recorded_header(header)
    header = header.is_a?(Hash) ? header : {}
    return if header.empty?
    return "#{MEDIA_PREFIX}#{header['media_type'].to_s.downcase}" if MEDIA_KEYS.any? { |key| header.key?(key) }

    header.keys.map(&:to_s).sort
  end

  def recorded_buttons(buttons)
    Array(buttons).each_with_index.with_object({}) do |(button, index), recorded|
      type = button.is_a?(Hash) ? button['type'].to_s.downcase : ''
      recorded[index] = type if %w[url copy_code].include?(type)
    end
  end

  def placeholder_keys(text)
    CampaignJourney::TemplatePlaceholders.keys(text).sort
  end

  def component(template, type)
    return unless template.is_a?(Hash)

    Array(template['components']).find { |item| item.is_a?(Hash) && item['type'].to_s.casecmp?(type) }
  end
end
