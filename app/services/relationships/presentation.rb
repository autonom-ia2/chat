class Relationships::Presentation
  SURFACES = Relationships::Configuration::SURFACES
  Invalid = Relationships::Configuration::Invalid

  def initialize(account)
    @account = account
  end

  def merge!(config, surfaces)
    raise Invalid, 'Unknown surfaces' unless surfaces.is_a?(Hash) && (surfaces.keys - SURFACES.keys).empty?

    surfaces.each { |surface, selection| config['surfaces'][surface] = validate!(surface, selection) }
  end

  def display!(config, definition, surfaces)
    validate_display!(definition, surfaces)
    SURFACES.select { |_, model| model == definition.attribute_model }.each_key do |surface|
      ids = selected_ids(config, surface, definition)
      ids.delete(definition.id)
      ids << definition.id if surfaces.include?(surface)
      config['surfaces'][surface] = { 'mode' => 'custom', 'ids' => ids }
    end
  end

  private

  def validate_display!(definition, surfaces)
    raise Invalid, 'display_on requires a definition' unless definition
    raise Invalid, 'display_on must contain unique surface names' unless surfaces.is_a?(Array) && surfaces.uniq == surfaces

    surfaces.each do |surface|
      raise Invalid, 'Wrong display surface' unless SURFACES[surface] == definition.attribute_model
    end
  end

  def selected_ids(config, surface, definition)
    selection = config['surfaces'][surface]
    return selection['ids'].dup if selection && selection['mode'] == 'custom'
    return [] unless surface == 'contact_sidebar'

    @account.custom_attribute_definitions.where(attribute_model: definition.attribute_model).where.not(id: definition.id).pluck(:id)
  end

  def validate!(surface, selection)
    raise Invalid, 'Companies are disabled' if SURFACES.fetch(surface) == 'company_attribute' && !@account.feature_enabled?('companies')

    validate_shape!(selection)
    ids = selection['ids']
    raise Invalid, 'Legacy mode cannot select fields' if selection['mode'] == 'legacy' && ids.any?

    matches = @account.custom_attribute_definitions.where(id: ids, attribute_model: SURFACES.fetch(surface)).count
    raise Invalid, 'Unknown definition or wrong entity' unless matches == ids.length

    selection
  end

  def validate_shape!(selection)
    raise Invalid, 'Invalid selection object' unless selection.is_a?(Hash) && (selection.keys - %w[mode ids]).empty?
    raise Invalid, 'Invalid presentation mode' unless %w[legacy custom].include?(selection['mode'])
    raise Invalid, 'ids must be unique positive integers' unless valid_ids?(selection['ids'])
  end

  def valid_ids?(ids)
    ids.is_a?(Array) && ids.uniq == ids && ids.all? { |id| id.is_a?(Integer) && id.positive? }
  end
end
