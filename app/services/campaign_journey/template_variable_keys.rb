# Where each variable of a WhatsApp template lives (#993, PRD §6.3): the binding keys of a
# journey campaign are the body variables as written ('1', 'nome'), the variables of a TEXT
# header prefixed with 'header.' ('header.1') and each URL button with a variable as
# 'button.<button index>' (Meta allows one variable per URL button). Read with
# CampaignJourney::TemplatePlaceholders (no regular expressions).
module CampaignJourney::TemplateVariableKeys
  HEADER_PREFIX = 'header.'.freeze
  BUTTON_PREFIX = 'button.'.freeze
  STATIC_BUTTON = { 'type' => 'static' }.freeze

  module_function

  def keys(template)
    body_keys(template) + header_keys(template) + button_keys(template)
  end

  def body_keys(template)
    CampaignJourney::TemplatePlaceholders.keys(component(template, 'BODY')&.dig('text'))
  end

  def header_keys(template)
    header = component(template, 'HEADER')
    return [] unless header && header['format'].to_s.casecmp?('TEXT')

    CampaignJourney::TemplatePlaceholders.keys(header['text']).map { |key| "#{HEADER_PREFIX}#{key}" }
  end

  def button_keys(template)
    Array(component(template, 'BUTTONS')&.dig('buttons')).each_with_index.filter_map do |button, index|
      next unless button['type'].to_s.casecmp?('URL')
      next if CampaignJourney::TemplatePlaceholders.keys(button['url']).empty?

      "#{BUTTON_PREFIX}#{index}"
    end
  end

  # { '1' => 'Ana', 'header.1' => 'Alfa', 'button.0' => 'abc' } into processed_params parts.
  def apply(processed_params, values)
    processed = processed_params.to_h.deep_dup
    values.each do |key, value|
      if key.start_with?(HEADER_PREFIX)
        processed['header'] = processed['header'].to_h.merge(key.delete_prefix(HEADER_PREFIX) => value)
      elsif key.start_with?(BUTTON_PREFIX)
        set_button(processed, Integer(key.delete_prefix(BUTTON_PREFIX), 10), value)
      else
        processed['body'] = processed['body'].to_h.merge(key => value)
      end
    end
    processed
  end

  # The array is positional (button index). Chatwoot's TemplateParameterConverterService only
  # keeps the component format when every entry is a Hash with a type, so the buttons without
  # a variable become STATIC_BUTTON, which TemplateProcessorService skips (not url, no parameter).
  def set_button(processed, index, value)
    buttons = Array(processed['buttons']).dup
    buttons[index] = buttons[index].to_h.merge('type' => buttons[index].to_h['type'] || 'url', 'parameter' => value)
    processed['buttons'] = buttons.map { |button| button.presence || STATIC_BUTTON.dup }
  end

  def component(template, type)
    Array(template&.dig('components')).find { |item| item['type'].to_s.casecmp?(type) }
  end
end
