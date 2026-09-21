# O RÓTULO DE UMA FALHA, para o log.
#
# Erro do connector sabe se descrever em categoria e porta (`etiqueta`), ambas nossas; qualquer
# outra exceção entra pela classe. Nunca a mensagem: ela pode carregar requisição assinada ou texto
# do portal, e foi por medo disso que o diagnóstico inteiro era descartado antes (20/09/2026).
module Autonomia::Agents::Tools::Rotulo
  def self.de(erro)
    return erro.etiqueta if erro.respond_to?(:etiqueta)

    erro.class.name
  end
end
