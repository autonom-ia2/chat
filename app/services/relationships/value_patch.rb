class Relationships::ValuePatch
  def initialize(record, model)
    @record = record
    @model = model
  end

  def update!(payload)
    validate_payload!(payload)
    # Configuration takes account -> definition. Values need only definition -> record;
    # never acquire the account lock after either of these locks.
    ActiveRecord::Base.transaction do
      definition = @record.account.custom_attribute_definitions.lock.find_by!(attribute_model: @model, attribute_key: payload['key'])
      @record.with_lock do
        Relationships::ValueValidator.new(definition).validate!(payload['value'])
        attributes = @record.custom_attributes.dup
        raise Relationships::Configuration::Conflict, 'Value changed; reload before saving' unless attributes[payload['key']] == payload['previous']

        payload['value'].nil? ? attributes.delete(payload['key']) : attributes[payload['key']] = payload['value']
        @record.update!(custom_attributes: attributes)
        attributes
      end
    end
  end

  private

  def validate_payload!(payload)
    return if payload.is_a?(Hash) && payload.keys.sort == %w[key previous value] && payload['key'].is_a?(String)

    raise Relationships::Configuration::Invalid, 'Expected key, value and previous'
  end
end
