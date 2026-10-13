# Os argumentos do modelo convertidos para o tipo que a ferramenta declarou (#1425, revisão).
#
# O modelo pode mandar texto num campo `integer`. Sem conversão, esse texto entra cru numa vaga sem
# aspas do corpo (`{"qtd": {{ qtd }}}`) e abre comentário, lista ou objeto. Aqui `integer` e `number`
# viram número, `boolean` só aceita true/false (ou o texto "true"/"false", que é o que a tela de teste
# manda), e `string` vira texto. Valor que não converte é recusado (`parametro_invalido`). nil passa
# como nil: é o "não informado" de um campo opcional. Argumento fora do param_schema passa como veio
# e é escapado na saída, como qualquer outro.
class Autonomia::Agents::Tools::ParamsTipados
  Recusa = Autonomia::Agents::Tools::HttpExecutor::ValorRecusado
  ESCALARES = [String, Numeric, TrueClass, FalseClass].freeze

  def self.converter(params, schema)
    new(params, schema).converter
  end

  def initialize(params, schema)
    @params = params
    @tipos = Array(schema).to_h { |param| [param['name'].to_s, param['type'].to_s] }
  end

  def converter
    @params.to_h { |nome, valor| [nome, converter_valor(@tipos[nome], valor)] }
  end

  private

  def converter_valor(tipo, valor)
    return valor if valor.nil? || tipo.nil?

    case tipo
    when 'integer' then inteiro(valor)
    when 'number' then numero(valor)
    when 'boolean' then booleano(valor)
    else texto(valor)
    end
  end

  def inteiro(valor)
    return valor if valor.is_a?(Integer)
    return valor.to_i if valor.is_a?(Float) && valor.finite? && valor == valor.to_i
    return recusar unless valor.is_a?(String)

    Integer(valor.strip, 10, exception: false) || recusar
  end

  def numero(valor)
    return valor if valor.is_a?(Integer)
    return finito(valor) if valor.is_a?(Float)
    return recusar unless valor.is_a?(String)

    bruto = valor.strip
    Integer(bruto, 10, exception: false) || finito(Float(bruto, exception: false) || recusar)
  end

  def finito(valor)
    valor.finite? ? valor : recusar
  end

  def booleano(valor)
    return valor if [true, false].include?(valor)
    return valor == 'true' if %w[true false].include?(valor)

    recusar
  end

  def texto(valor)
    ESCALARES.any? { |classe| valor.is_a?(classe) } ? valor.to_s : recusar
  end

  def recusar
    raise Recusa, 'parametro_invalido'
  end
end
