# As variáveis locais que um método monta antes do `permit` (#900):
#
#   permitted_attributes = [:name, :description, :event_name, :active]
#   permitted_attributes << :execution_delay if delayed_automations_enabled?
#   params.permit(*permitted_attributes, ...)
#
# Lidas em ordem, juntando tudo o que entra — inclusive o que entra sob
# condição: o formato diz o que a ação PODE aceitar. Quando a condição é
# recurso da conta, o `Espiao` marca o campo com `so_se`.
module Autonomia::Guide::Formatos::Locais
  Filtros = ::Autonomia::Guide::Formatos::Filtros
  ELEMENTOS = %i[<< push append].freeze
  LISTAS = %i[concat +].freeze

  module_function

  def coletar(corpo, modulo)
    escopo = Filtros::Escopo.new(modulo, {})
    em_ordem(corpo) { |node| anotar(node, escopo) }
    escopo
  end

  def em_ordem(node, &)
    return unless node

    yield node
    node.compact_child_nodes.each { |filho| em_ordem(filho, &) }
  end

  def anotar(node, escopo)
    case node
    when Prism::LocalVariableWriteNode then escopo.locais[node.name] = Filtros.do_codigo(node.value, escopo)
    when Prism::LocalVariableOperatorWriteNode then somar(escopo, node.name, Filtros.do_codigo(node.value, escopo))
    when Prism::CallNode then acrescentar(node, escopo)
    end
  end

  def acrescentar(node, escopo)
    alvo = node.receiver
    return unless alvo.is_a?(Prism::LocalVariableReadNode) && escopo.locais.key?(alvo.name)

    argumentos = Filtros.argumentos(node.arguments&.arguments || [], escopo)
    acrescimo = ELEMENTOS.include?(node.name) ? argumentos : lista_unica(node, argumentos)
    somar(escopo, alvo.name, acrescimo) if acrescimo
  end

  # `concat([...])` e `+ [...]`: o argumento único já é a lista.
  def lista_unica(node, argumentos)
    argumentos.first if LISTAS.include?(node.name) && argumentos.size == 1
  end

  def somar(escopo, nome, valor)
    atual = escopo.locais[nome]
    escopo.locais[nome] = atual.is_a?(Array) && valor.is_a?(Array) ? atual + valor : Filtros::Dinamico.new(nome.to_s)
  end
end
