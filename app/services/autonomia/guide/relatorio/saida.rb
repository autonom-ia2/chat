# O relatório em JSON, dentro do teto da ferramenta (#3158).
#
# A saída de ferramenta é cortada em 8.000 caracteres pelo `Bound`, e corte cego parte o JSON no meio. Aqui a
# lista (`linhas` do ranking, `pontos` da série) perde itens do fim até caber, e a resposta diz quantos ficaram.
module Autonomia::Guide::Relatorio::Saida
  # Abaixo do teto do `Bound`, como a `ler_da_conta` (`GuiaLeitura::TETO`).
  TETO = 6_000
  LISTAS = %i[linhas pontos].freeze

  module_function

  def caber(relatorio)
    texto = relatorio.to_json
    return texto if texto.length <= TETO

    chave = LISTAS.find { |nome| relatorio[nome].is_a?(Array) }
    return texto.first(TETO) if chave.nil?

    encolher(relatorio, chave)
  end

  # Corta pela metade até caber e devolve só o que cabe, com a conta do que ficou de fora.
  def encolher(relatorio, chave)
    lista = relatorio[chave]
    mantidos = lista.size
    loop do
      mantidos /= 2
      texto = relatorio.merge(chave => lista.first(mantidos)).merge(cortado: "Mostrando #{mantidos} de #{lista.size}.").to_json
      return texto if texto.length <= TETO || mantidos.zero?
    end
  end
end
