# Schema estrito do provedor (structured outputs): todo objeto, em todo nível, lista TODAS as propriedades em `required`
# e não aceita outras. Sem isso o provedor recusa a chamada e o recurso falha em silêncio (#1428 t6d, rodada 3 do eval:
# toda prova "indisponível"). Os specs dublam o provedor, então a regra é conferida aqui. Cada campo declara o tipo, e
# toda lista declara o tipo do item.
module SchemaEstritoHelper
  def expect_schema_estrito(schema)
    objetos = objetos_do_schema(schema)
    expect(objetos).not_to be_empty
    objetos.each do |objeto|
      expect(Array(objeto[:required]).map(&:to_s)).to match_array(objeto[:properties].to_h.keys.map(&:to_s))
      expect(objeto[:additionalProperties]).to be(false)
      objeto[:properties].to_h.each { |nome, campo| expect_campo_tipado(nome, campo) }
    end
  end

  def expect_campo_tipado(nome, campo)
    expect(campo[:type]).to be_present, "campo #{nome} sem type"
    expect(campo.dig(:items, :type)).to be_present, "lista #{nome} sem o type do item" if Array(campo[:type]).include?('array')
  end

  def objetos_do_schema(parte)
    return [] unless parte.is_a?(Hash)

    proprios = parte[:type] == 'object' ? [parte] : []
    proprios + parte.values.flat_map { |valor| objetos_do_schema(valor) }
  end
end

RSpec.configure { |config| config.include SchemaEstritoHelper }
