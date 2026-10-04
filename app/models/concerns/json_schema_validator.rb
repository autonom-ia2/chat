# Valida uma coluna JSON contra um esquema (JSON Schema, draft 7, pela gem json_schemer).
#
#   validates :settings, json_schema: { schema: SETTINGS_PARAMS_SCHEMA }
#   validates :conditions, json_schema: { schema: ->(regra) { AutomationRuleSchema.conditions(regra) } }
#
# O esquema é um Hash (ou o JSON dele) ou uma lambda que recebe o registro. A lambda é chamada com
# `nil` para o esquema geral, sem registro: é o que o Guia lê (`Autonomia::Guide::Formatos::Esquemas`).
#
# Anotações começadas por `x-` (`x-da-conta`, `x-sem-volta`) e `description` são só para quem lê o
# esquema: o validador as ignora.
#
# O erro vai na chave do campo de dentro (`address/street`), como sempre foi. Coluna que é lista não
# tem nome de campo na raiz: o erro vai no próprio atributo, com o ponteiro (`/0/action_name ...`).
class JsonSchemaValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    schemer = JSONSchemer.schema(esquema(record), formats: JsonSchemaFormatos::TODOS)
    schemer.validate(value).each { |error| format_and_append_error(error, record, attribute) }
  end

  # O esquema, com chaves em texto. Sem registro, o geral.
  def esquema(record = nil)
    schema = options[:schema]
    schema = schema.call(record) if schema.respond_to?(:call)
    schema.is_a?(String) ? JSON.parse(schema) : schema.deep_stringify_keys
  end

  # O texto de cada recusa. O que não está aqui é tipo errado ("must be of type integer").
  MESSAGES = {
    'minimum' => ->(error) { "must be greater than or equal to #{error['schema']['minimum']}" },
    'maximum' => ->(error) { "must be less than or equal to #{error['schema']['maximum']}" },
    'enum' => ->(error) { "#{error['data'].to_json} is not one of: #{error['schema']['enum'].join(', ')}" },
    'const' => ->(error) { "must be #{error['schema']['const'].to_json}" },
    'schema' => ->(_error) { 'is not allowed' },
    'format' => ->(error) { "must be a valid #{error['schema']['format']}" },
    'minItems' => ->(error) { "is too short (minimum is #{error['schema']['minItems']})" },
    'minLength' => ->(error) { "is too short (minimum is #{error['schema']['minLength']})" },
    'maxItems' => ->(error) { "is too long (maximum is #{error['schema']['maxItems']})" },
    'maxLength' => ->(error) { "is too long (maximum is #{error['schema']['maxLength']})" }
  }.freeze

  private

  def format_and_append_error(error, record, attribute)
    return handle_required(error, record, attribute) if error['type'] == 'required'

    message = MESSAGES[error['type']]&.call(error) || "must be of type #{error['type'] == 'object' ? 'hash' : error['type']}"
    add(record, attribute, error, message)
  end

  def handle_required(error, record, attribute)
    error['details']['missing_keys'].each do |missing|
      next record.errors.add(missing, 'is required') unless lista?(error['data_pointer'])

      record.errors.add(attribute, "#{error['data_pointer']}/#{missing} is required")
    end
  end

  def add(record, attribute, error, message)
    pointer = error['data_pointer']
    return record.errors.add(attribute, [pointer.presence, message].compact.join(' ')) if pointer.blank? || lista?(pointer)

    record.errors.add(pointer.delete_prefix('/'), message)
  end

  # O ponteiro começa num índice: a coluna é uma lista.
  def lista?(pointer)
    primeiro = pointer.to_s.delete_prefix('/').split('/').first
    primeiro.present? && Integer(primeiro, exception: false).present?
  end
end
