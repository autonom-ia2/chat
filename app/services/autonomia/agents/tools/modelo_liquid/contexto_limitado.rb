# Os limites do Liquid conferem entre nós: a cadeia de filtros de um {{ }} rodava inteira antes (100 MB e 10 s num nó
# só, na revisão adversarial). Aqui cada filtro confere o prazo antes e o tamanho do que devolve.
class Autonomia::Agents::Tools::ModeloLiquid::ContextoLimitado < Liquid::Context
  def invoke(metodo, *args)
    resource_limits.conferir_prazo
    resultado = super
    resource_limits.conferir_tamanho(resultado)
    resultado
  end
end
