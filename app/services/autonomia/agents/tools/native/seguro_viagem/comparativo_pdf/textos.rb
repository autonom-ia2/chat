# OS TEXTOS do comparativo que saem só de números da cotação (#3211): a lista de idades com "ano"/"anos" certo e o
# preço por pessoa com as idades do mesmo preço juntas. Funções puras, sem Prawn, para o spec ler sem montar o PDF.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Textos
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  CONECTORES = { words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ' }.freeze

  module_function

  # [47, 19, 12] -> "47, 19 e 12 anos"; [19, 1] -> "19 anos e 1 ano"; [72, 19, 1] -> "72, 19 anos e 1 ano".
  # A unidade vai depois do último número de cada sequência com a mesma unidade.
  def idades(lista)
    itens = lista.each_with_index.map do |idade, indice|
      proxima = lista[indice + 1]
      fim_da_sequencia = proxima.nil? || unidade(proxima) != unidade(idade)
      fim_da_sequencia ? "#{idade} #{unidade(idade)}" : idade.to_s
    end
    itens.to_sentence(**CONECTORES)
  end

  # O preço por pessoa, idades do mesmo preço numa linha só: [["47, 19 e 12 anos", "R$ 120,00 cada"]], na ordem em que
  # as idades aparecem. Vazio com um viajante só (o preço dele é o total), quando alguém fica sem preço ou quando a
  # soma não fecha com o total da Universal: aí o PDF mostra só o total e não inventa divisão.
  def precos_por_pessoa(plano, lista_de_idades)
    valores = SeguroViagem::Faixas.precos_por_pessoa(plano, lista_de_idades)
    return [] if lista_de_idades.size < 2 || !fecha_com_o_total?(plano, valores)

    lista_de_idades.zip(valores).group_by { |_, valor| BigDecimal(valor.to_s) }.map do |valor, pares|
      [idades(pares.map(&:first)), "#{SeguroViagem::Dinheiro.brl(valor)}#{' cada' if pares.size > 1}"]
    end
  end

  def fecha_com_o_total?(plano, valores)
    return false if plano['preco_total'].blank? || valores.include?(nil)

    valores.sum { |valor| BigDecimal(valor.to_s) } == BigDecimal(plano['preco_total'].to_s)
  end

  def unidade(idade)
    idade.to_i == 1 ? 'ano' : 'anos'
  end

  private_class_method :fecha_com_o_total?, :unidade
end
