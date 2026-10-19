# #1426 (revisão adversarial) — largura e altura de uma página de PDF, em pontos, já multiplicadas pela /UserUnit (PDF 1.6:
# o tamanho de cada unidade; sem ela, 1). A MediaBox, cada número dela e a UserUnit podem vir por referência indireta
# ("5 0 R"): o leitor (`objects.deref`) resolve. O que não for número depois disso devolve nil, e a página não vai para
# o ImageMagick. Não usa Page#width/height do pdf-reader, que levantam ArgumentError com a MediaBox indireta.
module Autonomia::Agents::Knowledge::Processors::TamanhoDaPagina
  module_function

  def em_pontos(page)
    objetos = page.objects
    caixa = objetos.deref(page.attributes[:MediaBox])
    caixa = caixa.is_a?(Array) ? caixa.map { |valor| objetos.deref(valor) } : []
    unidade = objetos.deref(page.attributes.fetch(:UserUnit, 1))
    return unless caixa.size == 4 && caixa.all?(Numeric) && unidade.is_a?(Numeric) && unidade.positive?

    esquerda, baixo, direita, cima = caixa
    [(direita - esquerda).abs * unidade, (cima - baixo).abs * unidade]
  end
end
