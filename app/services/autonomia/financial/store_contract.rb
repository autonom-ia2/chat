# frozen_string_literal: true

require 'json'
require 'json_schemer'

# E0 boundary schemas. Valid payloads are not proof of identity or entitlement.
class Autonomia::Financial::StoreContract
  SCHEMA_PATH = File.expand_path('../../../../config/autonomia_store/contract.v1.json', __dir__).freeze

  def self.validate!(definition, payload)
    schema = JSON.parse(File.read(SCHEMA_PATH))
    schema.fetch('definitions').fetch(definition)
    schema['$ref'] = "#/definitions/#{definition}"
    errors = JSONSchemer.schema(schema).validate(payload).to_a
    raise Autonomia::Financial::StoreContractError, errors.map { |error| error.fetch('data_pointer') }.uniq if errors.any?

    payload
  end
end
