class Relationships::ValueValidator
  def initialize(definition)
    @definition = definition
  end

  def validate!(value)
    unless [nil, ''].include?(@definition.regex_pattern)
      raise Relationships::Configuration::Invalid,
            'Use the legacy editor for attributes with legacy validation'
    end
    return if value.nil?

    type = @definition.attribute_display_type
    validator = { 'text' => :text?, 'number' => :number?, 'currency' => :number?, 'percent' => :number?, 'checkbox' => :checkbox?, 'list' => :list?,
                  'link' => :url?, 'date' => :date? }[type]
    raise Relationships::Configuration::Invalid, 'Invalid attribute value' unless validator && send(validator, value)
  rescue Date::Error
    raise Relationships::Configuration::Invalid, 'Invalid attribute value'
  end

  private

  def text?(value)
    value.is_a?(String)
  end

  def number?(value)
    value.is_a?(Numeric) && value.finite?
  end

  def checkbox?(value)
    [true, false].include?(value)
  end

  def list?(value)
    value.is_a?(String) && @definition.attribute_values.include?(value)
  end

  def url?(value)
    return false unless value.is_a?(String)

    uri = URI.parse(value)
    %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def date?(value)
    value.is_a?(String) && value.length == 10 && Date.iso8601(value).iso8601 == value
  end
end
