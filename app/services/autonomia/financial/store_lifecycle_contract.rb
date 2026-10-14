# frozen_string_literal: true

class Autonomia::Financial::StoreLifecycleContract
  SCHEMA_PATH = File.expand_path('../../../../config/autonomia_store/lifecycle.v1.json', __dir__).freeze

  def self.validate!(definition, payload)
    base = JSON.parse(File.read(Autonomia::Financial::StoreCheckoutContract::SCHEMA_PATH))
    schema = JSON.parse(File.read(SCHEMA_PATH))
    schema.fetch('definitions').fetch(definition)
    schema['$ref'] = "#/definitions/#{definition}"
    resolver = proc do |uri|
      origin = uri.dup
      origin.fragment = nil
      raise JSONSchemer::UnknownRef, uri.to_s unless origin.to_s == base.fetch('$id')

      base
    end
    errors = JSONSchemer.schema(schema, ref_resolver: resolver).validate(payload).to_a
    raise Autonomia::Financial::StoreContractError, errors.map { |error| error.fetch('data_pointer') }.uniq if errors.any?

    payload
  end
end
