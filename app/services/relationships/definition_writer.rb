class Relationships::DefinitionWriter
  Invalid = Relationships::Configuration::Invalid
  Conflict = Relationships::Configuration::Conflict
  EDITABLE = Relationships::Configuration::EDITABLE
  CREATION = Relationships::Configuration::CREATION
  TYPES = Relationships::Configuration::TYPES

  def initialize(account)
    @account = account
  end

  def save!(data)
    validate_shape!(data)
    definition = data.key?('id') ? existing_definition(data) : new_definition(data)
    raise Invalid, 'Companies are disabled' if definition.company_attribute? && !@account.feature_enabled?('companies')

    definition.assign_attributes(data.slice(*EDITABLE))
    validate_name!(definition)
    validate_options!(definition) if definition.new_record? || data.key?('attribute_values')
    definition.save!
    definition
  end

  private

  def validate_shape!(data)
    allowed = EDITABLE + CREATION + %w[id revision]
    raise Invalid, 'Invalid definition object' unless data.is_a?(Hash) && (data.keys - allowed).empty?

    data.slice(*EDITABLE).each do |key, value|
      valid = key == 'attribute_values' ? valid_options?(value) : value.nil? || value.is_a?(String)
      raise Invalid, 'Invalid definition field' unless valid
    end
  end

  def valid_options?(value)
    value.is_a?(Array) && value.all? { |option| option.is_a?(String) && option.present? }
  end

  def existing_definition(data)
    raise Invalid, 'id must be an integer' unless data['id'].is_a?(Integer)
    raise Invalid, 'Type, entity and key are immutable' if data.keys.intersect?(CREATION)

    definition = @account.custom_attribute_definitions.lock.find(data['id'])
    raise Conflict, 'Definition changed; reload before saving' unless data['revision'] == definition.updated_at.iso8601(6)

    definition
  end

  def new_definition(data)
    description = data['attribute_description']
    raise Invalid, 'Description is required' unless description.is_a?(String) && description.strip.present?
    raise Invalid, 'Unsupported type' unless TYPES.include?(data['attribute_display_type'])
    raise Invalid, 'Unsupported entity' unless CustomAttributeDefinition.attribute_models.key?(data['attribute_model'])
    raise Invalid, 'Key must be a string' unless data['attribute_key'].is_a?(String)

    @account.custom_attribute_definitions.new(data.slice(*CREATION))
  end

  def validate_name!(definition)
    duplicate = @account.custom_attribute_definitions.where(attribute_model: definition.attribute_model)
                        .where('lower(attribute_display_name) = ?', definition.attribute_display_name.to_s.strip.downcase)
    duplicate = duplicate.where.not(id: definition.id) if definition.persisted?
    raise Invalid, 'Name already exists; choose another name' if duplicate.exists?
  end

  def validate_options!(definition)
    return unless definition.list?
    return if definition.attribute_values.present? && definition.attribute_values.uniq == definition.attribute_values

    raise Invalid, 'List requires unique options'
  end
end
