# Leitura em SQL de uma chave de uma coluna JSON que pode estar gravada de dois jeitos (chat#1709, revisão): como objeto
# (`{"c2y_hidden":true}`) ou como STRING JSON com o objeto dentro (`"{\"c2y_hidden\":true}"`, a codificação dupla do
# `store ... coder: JSON` de Message#content_attributes, o caso comum em produção). `->>` direto só lê o objeto; o
# `::text LIKE` só casa a string. Aqui a coluna é normalizada para objeto antes de ler a chave, nos dois tipos (`json` e
# `jsonb`). Sem regex nem LIKE.
module Waha::RichNative::JsonColumn
  TYPES = { json: 'json_typeof', jsonb: 'jsonb_typeof' }.freeze

  module_function

  # A coluna como objeto. column: 'messages.content_attributes'; type: :json | :jsonb.
  def object(column, type)
    "(CASE WHEN #{TYPES.fetch(type)}(#{column}) = 'string' THEN (#{column} #>> '{}')::#{type} ELSE #{column} END)"
  end

  # O texto da chave, ou NULL (ausente ou JSON null).
  def text(column, type, key)
    "(#{object(column, type)} ->> #{ActiveRecord::Base.connection.quote(key)})"
  end

  # A chave PRESENTE no mesmo sentido do `present?` do Ruby (Waha::RichNative::TurnKinds.deleted?): não nula, nem texto
  # em branco, nem false, nem lista ou objeto vazios.
  def present(column, type, key)
    value = text(column, type, key)
    "(#{value} IS NOT NULL AND btrim(#{value}) NOT IN ('', 'false', '[]', '{}'))"
  end
end
