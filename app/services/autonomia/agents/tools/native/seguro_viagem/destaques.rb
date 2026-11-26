# OS DESTAQUES de uma cotação do Seguro Viagem (#3226): mais econômica, mais recomendada e maior cobertura. É o ponto
# único da escolha: o PDF (`ComparativoPdf`, a capa, o resumo e os selos dos cartões) e o resumo que o modelo lê
# (`Planos.resumo`) passam por aqui, para a mensagem e o PDF nunca destacarem planos diferentes.
#
# A regra dos rótulos é a de `ComparativoPdf::Rotulos` (com a `Pontuacao`), sempre sobre os mesmos planos e na mesma
# ordem: os de viagem única, do mais barato ao mais caro (`Ordem.por_preco`); só com anuais, os anuais. Anual que veio
# junto com planos de viagem única não tem destaque: ele não se compara com o preço de uma viagem só.
module Autonomia::Agents::Tools::Native::SeguroViagem::Destaques
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  # O nome de cada rótulo no resumo ao modelo. `opcao_disponivel`: a cotação com um plano só.
  NOMES = { economica: 'mais_economica', recomendada: 'mais_recomendada', maior_cobertura: 'maior_cobertura',
            disponivel: 'opcao_disponivel' }.freeze

  module_function

  # -> os planos que os rótulos olham, na ordem do PDF.
  def comparaveis(planos)
    todos = SeguroViagem::ComparativoPdf::Ordem.por_preco(planos.to_a)
    todos.reject { |plano| SeguroViagem::Planos.anual?(plano) }.presence || todos
  end

  # -> um símbolo de `NOMES` (ou nil) por plano, na ordem de `comparaveis`.
  def rotulos(comparaveis)
    SeguroViagem::ComparativoPdf::Rotulos.de(comparaveis)
  end

  # -> { código do plano => nome do rótulo }, só dos planos com destaque.
  def por_codigo(planos)
    lista = comparaveis(planos)
    lista.zip(rotulos(lista)).each_with_object({}) do |(plano, rotulo), destaques|
      destaques[plano['codigo']] = NOMES[rotulo] unless rotulo.nil?
    end
  end
end
