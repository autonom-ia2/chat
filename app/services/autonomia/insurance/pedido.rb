# A IDENTIDADE DE UM PEDIDO DE COTAÇÃO (entrega 10): o que diz se dois pedidos são o mesmo pedido.
#
# "E aí, saiu?" não pode abrir cotação nova. O modelo chama a ferramenta de novo com os mesmos dados,
# e até 10/09/2026 `ToolRun.open!` supersedia a execução viva e abria OUTRA cotação no portal do
# corretor. Distinguir a pergunta do pedido novo é do modelo; o que o código faz é comparar DADOS.
#
# Compara-se a entrada NORMALIZADA pelo adapter (o `quote/validate` gratuito a devolve), e não o
# texto cru que o modelo escreveu: a duplicata mais provável é o mesmo pedido com os mesmos valores
# padrão — `estado civil: 1` escrito numa chamada e omitido na outra. Os padrões moram no adapter;
# copiá-los para cá é valor em dois lugares (proibido pelo termo 1 da entrega 2).
#
# O digest é curto e estável: chaves em ordem, produto junto. Não carrega dado pessoal — é o que
# fica gravado na execução (`ToolRun::PEDIDO`) e no log.
module Autonomia::Insurance::Pedido
  TAMANHO = 32

  def self.digest(produto, entrada)
    return nil unless entrada.is_a?(Hash) && entrada.present?

    Digest::SHA256.hexdigest(JSON.generate(canonico('produto' => produto.to_s, 'entrada' => entrada)))[0, TAMANHO]
  end

  # Chaves em ordem, em todo nível; listas como vieram (o adapter já ordena as de códigos).
  def self.canonico(valor)
    case valor
    when Hash then valor.keys.map(&:to_s).sort.index_with { |chave| canonico(valor[chave] || valor[chave.to_sym]) }
    when Array then valor.map { |item| canonico(item) }
    else valor
    end
  end
end
