# frozen_string_literal: true

class Autonomia::Financial::StorePublicationContract
  SCHEMA_PATH = File.expand_path('../../../../config/autonomia_store/publication.v1.json', __dir__).freeze

  def self.validate!(definition, payload)
    schema = JSON.parse(File.read(Autonomia::Financial::StoreContract::SCHEMA_PATH))
    extension = JSON.parse(File.read(SCHEMA_PATH))
    schema.fetch('definitions').merge!(extension.fetch('definitions'))
    schema.fetch('definitions').fetch(definition)
    schema['$ref'] = "#/definitions/#{definition}"
    errors = JSONSchemer.schema(schema).validate(payload).to_a
    raise Autonomia::Financial::StoreContractError, errors.map { |error| error.fetch('data_pointer') }.uniq if errors.any?

    if %w[serviceDraftRequest publicationRequest publication].include?(definition) && payload.fetch('group') != payload.fetch('target').fetch('type')
      raise Autonomia::Financial::StoreContractError, ['/group']
    end

    payload
  end
end
