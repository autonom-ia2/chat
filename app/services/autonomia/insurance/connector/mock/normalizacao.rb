# A ENTRADA COMO O ADAPTER A ENTENDE (entrega 10), imitada pelo mock: padrão de `escolha` para o que
# NÃO VEIO, chaves em ordem — e nada mais. `null` e `''` são valores (o montador do adapter os manda
# como vieram), texto não perde espaço, lista não muda de ordem. É o que o consumidor compara para
# não abrir cotação nova para o mesmo pedido — e por isso o mock precisa devolvê-la como o real,
# senão o teste do "e aí, saiu?" se aprovaria contra um adapter que não existe.
module Autonomia::Insurance::Connector::Mock::Normalizacao
  module_function

  def normalizada(campos, input)
    copia = input.to_h.deep_dup.deep_stringify_keys
    campos.each do |c|
      next unless c['origem'] == 'escolha' && c.key?('padrao') && !presente?(copia, c['campo'])

      definir_em(copia, c['campo'], c['padrao'])
    end
    canonica(copia)
  end

  # Só o que não veio é ausente: a chave escrita com `nil` veio.
  def presente?(hash, caminho)
    *pais, folha = caminho.split('.')
    alvo = pais.reduce(hash) { |atual, parte| atual.is_a?(Hash) ? atual[parte] : nil }
    alvo.is_a?(Hash) && alvo.key?(folha)
  end

  # Cria o ancestral que não existe; o que existe e não é Hash fica como veio (o montador do adapter
  # o espalha assim), e nada é escrito abaixo dele.
  def definir_em(hash, caminho, valor)
    *pais, folha = caminho.split('.')
    alvo = pais.reduce(hash) do |atual, parte|
      break atual unless atual.is_a?(Hash)

      atual[parte] = {} unless atual.key?(parte)
      atual[parte]
    end
    alvo[folha] = valor if alvo.is_a?(Hash)
  end

  def canonica(valor)
    case valor
    when Hash then valor.keys.map(&:to_s).sort.index_with { |chave| canonica(valor[chave] || valor[chave.to_sym]) }
    when Array then valor.map { |item| canonica(item) }
    else valor
    end
  end
end
