# Presentation is account-wide; attribute values stay on their original records.
class Relationships::Configuration
  class Invalid < StandardError; end
  class Conflict < StandardError; end

  SURFACES = { 'contact_sidebar' => 'contact_attribute', 'contact_details' => 'contact_attribute',
               'company_details' => 'company_attribute' }.freeze
  EDITABLE = %w[attribute_display_name attribute_description attribute_values].freeze
  CREATION = %w[attribute_key attribute_model attribute_display_type].freeze
  TYPES = %w[text number link date list checkbox].freeze

  def initialize(account)
    @account = account
  end

  def read
    config = @account.settings&.fetch('relationships', nil)
    return { 'version' => 1, 'revision' => 0, 'surfaces' => {} } unless config

    config = config.deep_dup
    definitions = @account.custom_attribute_definitions.pluck(:id, :attribute_model).to_h
    config['surfaces'].each do |surface, selection|
      selection['ids'].select! { |id| definitions[id] == SURFACES.fetch(surface) }
    end
    config
  end

  def update!(payload)
    validate_payload!(payload)
    @account.with_lock { persist!(payload) }
  end

  def serialize_definition(definition)
    definition.as_json.merge('revision' => definition.updated_at.iso8601(6))
  end

  private

  def validate_payload!(payload)
    allowed = %w[revision surfaces definition display_on]
    raise Invalid, 'Invalid object or unknown fields' unless payload.is_a?(Hash) && (payload.keys - allowed).empty?
    raise Invalid, 'revision must be an integer' unless payload['revision'].is_a?(Integer)
  end

  def persist!(payload)
    config = read.deep_dup
    raise Conflict, 'Configuration changed; reload before saving' unless payload['revision'] == config['revision']

    definition = Relationships::DefinitionWriter.new(@account).save!(payload['definition']) if payload.key?('definition')
    presentation = Relationships::Presentation.new(@account)
    presentation.merge!(config, payload.fetch('surfaces', {}))
    presentation.display!(config, definition, payload['display_on']) if payload.key?('display_on')
    config['revision'] += 1
    @account.update!(settings: (@account.settings || {}).merge('relationships' => config))
    { configuration: config, definition: definition && serialize_definition(definition) }
  end
end
