# A condição de um "se", de um "esperar até" ou de um filtro do gatilho (#2414 F3). Estruturada, nunca texto:
# `{"campo": {"$valor": "conversa.status"}, "op": "igual", "valor": "resolved"}`, ou `todas`/`alguma` de outras.
#
# Valor ausente não é erro: "vazio" e "preenchido" respondem por ele. As comparações o tratam como texto vazio
# ("diferente" e "não contém" dão verdadeiro) e, para "maior" e "menor", dão falso. "Igual" com os dois lados
# números compara como número (10 é igual a "10.0"); senão, como texto.
class Autonomia::Automacao::Condicao
  OPERACOES = {
    'igual' => ->(atual, valor) { !atual.is_a?(Array) && igual?(atual, valor) },
    'diferente' => ->(atual, valor) { !OPERACOES['igual'].call(atual, valor) },
    'contem' => ->(atual, valor) { Array(atual).map(&:to_s).include?(valor.to_s) },
    'nao_contem' => ->(atual, valor) { !OPERACOES['contem'].call(atual, valor) },
    'vazio' => ->(atual, _valor) { atual.blank? },
    'preenchido' => ->(atual, _valor) { atual.present? },
    'maior' => ->(atual, valor) { comparar(atual, valor) { |esquerda, direita| esquerda > direita } },
    'menor' => ->(atual, valor) { comparar(atual, valor) { |esquerda, direita| esquerda < direita } }
  }.freeze

  def self.igual?(atual, valor)
    esquerda = numero(atual)
    direita = numero(valor)
    esquerda && direita ? esquerda == direita : atual.to_s == valor.to_s
  end

  def self.comparar(atual, valor)
    esquerda = numero(atual)
    direita = numero(valor)
    esquerda.nil? || direita.nil? ? false : yield(esquerda, direita)
  end

  def self.numero(valor)
    return valor if valor.is_a?(Numeric)

    BigDecimal(valor.to_s, exception: false)
  end

  # Os caminhos de valor que a condição lê, para o salvar conferir.
  def self.caminhos(condicao)
    return condicao.values_at('todas', 'alguma').compact.flatten.flat_map { |filha| caminhos(filha) } unless condicao.key?('campo')

    [condicao.dig('campo', '$valor')]
  end

  def initialize(condicao, valores)
    @condicao = condicao
    @valores = valores
  end

  def verdadeira?
    return @condicao['todas'].all? { |filha| self.class.new(filha, @valores).verdadeira? } if @condicao.key?('todas')
    return @condicao['alguma'].any? { |filha| self.class.new(filha, @valores).verdadeira? } if @condicao.key?('alguma')

    OPERACOES.fetch(@condicao['op']).call(@valores.ler(@condicao.dig('campo', '$valor')), @condicao['valor'])
  end
end
