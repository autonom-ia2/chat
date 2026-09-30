# Strict request boundary for the optional, composed opportunity registration.
# Legacy cards#create payloads do not pass through this contract.
class Crm::Cards::RegistrationInput
  class Invalid < StandardError
    attr_reader :section, :fields, :code, :matches

    def initialize(section, fields = {}, code: 'invalid_input', matches: [])
      @section = section
      @fields = fields
      @code = code
      @matches = matches
      super(code)
    end
  end

  CONTACT_KEYS = %w[name email phone_number additional_attributes custom_attributes].freeze
  COMPANY_KEYS = %w[name domain additional_attributes custom_attributes].freeze

  def self.contact_identity(attributes)
    email = attributes['email']&.strip&.downcase.presence
    phone = attributes['phone_number']&.strip.presence
    if phone&.start_with?('+')
      parsed = TelephoneNumber.parse(phone)
      phone = parsed.e164_number if parsed.valid?
    end
    { 'email' => email, 'phone_number' => phone }
  end

  def initialize(input)
    @input = input
  end

  def perform
    object!(@input, %w[mode contact company], 'contact')
    raise Invalid.new('contact', { mode: 'invalid' }) unless @input['mode'] == 'new'

    contact = attributes!(@input['contact'], CONTACT_KEYS, %w[city country], 'contact')
    company = company_input
    { contact: contact.merge(self.class.contact_identity(contact)), company: company }
  end

  private

  def object!(input, allowed, section)
    raise Invalid.new(section, { base: 'invalid' }) unless input.is_a?(Hash) && (input.keys - allowed).empty?
  end

  def attributes!(input, keys, extra_keys, section)
    object!(input, keys, section)
    raise Invalid.new(section, { name: 'required' }) unless input['name'].is_a?(String) && input['name'].strip.present?

    strings = keys - %w[additional_attributes custom_attributes]
    optional_strings!(input, strings, section)
    result = input.deep_dup
    strings.each { |key| result[key] = result[key].strip.presence if result[key].is_a?(String) }
    validate_objects!(result, extra_keys, section)
    result
  end

  def validate_objects!(attributes, extra_keys, section)
    %w[additional_attributes custom_attributes].each do |key|
      raise Invalid.new(section, { key => 'invalid' }) if attributes.key?(key) && !attributes[key].is_a?(Hash)
    end
    extra = attributes['additional_attributes'] || {}
    object!(extra, extra_keys, section)
    optional_strings!(extra, extra_keys, section)
  end

  def optional_strings!(input, keys, section)
    keys.each do |key|
      value = input[key]
      raise Invalid.new(section, { key => 'invalid' }) unless value.nil? || value.is_a?(String)
    end
  end

  def company_input
    input = @input.fetch('company', { 'mode' => 'none' })
    object!(input, %w[mode id attributes], 'company')
    case input['mode']
    when 'none'
      object!(input, %w[mode], 'company')
    when 'existing'
      object!(input, %w[mode id], 'company')
      raise Invalid.new('company', { id: 'invalid' }) unless input['id'].is_a?(Integer) && input['id'].positive?
    when 'new'
      object!(input, %w[mode attributes], 'company')
      attributes = attributes!(input['attributes'], COMPANY_KEYS, %w[city], 'company')
      return input.merge('attributes' => attributes)
    else
      raise Invalid.new('company', { mode: 'invalid' })
    end
    input
  end
end
