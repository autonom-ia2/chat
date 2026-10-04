# O número que uma vigia tira de uma leitura da conta (#935).
#
# A leitura é a mesma de `ler_da_conta`: o corpo JSON que a tela recebe. Daqui sai um número só, por
# um de quatro jeitos declarados na vigia, sem nenhum conhecimento do que a leitura é:
#
# - `contagem`: quantos itens (com `onde`, só os que têm aqueles valores);
# - `soma` e `maior`: de um campo numérico dos itens (`maior` também diz qual item);
# - `valor`: um número da própria resposta.
#
# Os itens são a lista da resposta: ela mesma, o `payload` ou a primeira lista que a resposta tiver.
# O campo desce por ponto ("disparos.ultimas_24h"). Nada de texto sai daqui: só número e id.
class Autonomia::Guide::Medida
  Resultado = Struct.new(:valor, :item_id, keyword_init: true)
  DA_LISTA = %w[contagem soma maior].freeze

  def initialize(medida)
    @tipo = medida['tipo'].to_s
    @campo = medida['campo'].to_s
    @onde = medida['onde'].to_h
  end

  # nil quando a resposta não tem o que a medida pede.
  def de(corpo)
    return numero(corpo)&.then { |valor| Resultado.new(valor: valor) } if @tipo == 'valor'

    lista = itens(corpo)
    send(@tipo, lista) if lista && DA_LISTA.include?(@tipo)
  end

  private

  def contagem(lista) = Resultado.new(valor: lista.size)
  def soma(lista) = Resultado.new(valor: lista.sum { |item| numero(item) || 0 })

  def itens(corpo)
    lista = lista_de(corpo)
    lista&.select { |item| item.is_a?(Hash) && @onde.all? { |chave, valor| item[chave] == valor } }
  end

  def lista_de(corpo)
    return corpo if corpo.is_a?(Array)
    return unless corpo.is_a?(Hash)
    return corpo['payload'] if corpo['payload'].is_a?(Array)

    corpo.values.find { |valor| valor.is_a?(Array) }
  end

  # O maior e qual item é; lista sem o campo, zero.
  def maior(lista)
    item = lista.select { |candidato| numero(candidato) }.max_by { |candidato| numero(candidato) }
    return Resultado.new(valor: 0) if item.nil?

    Resultado.new(valor: numero(item), item_id: (item['id'] if item['id'].is_a?(Integer)))
  end

  def numero(objeto)
    valor = @campo.split('.').reduce(objeto) { |atual, chave| atual.is_a?(Hash) ? atual[chave] : nil }
    valor.is_a?(Numeric) ? valor : nil
  end
end
