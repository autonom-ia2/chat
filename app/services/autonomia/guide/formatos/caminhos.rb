# Onde, dentro do corpo, um nó do Prism lê (#900): `[]` para `params`,
# `['custom_role']` para `params.require(:custom_role)`, `['channel', 'type']`
# para `params[:channel][:type]`. Nil quando o nó não lê de `params`.
#
# Chave que não é literal (`params[k]`, `params[root_key]`) não é caminho: não
# é nome de campo.
class Autonomia::Guide::Formatos::Caminhos
  Fontes = ::Autonomia::Guide::Formatos::Fontes

  def initialize(klass, coleta)
    @klass = klass
    @coleta = coleta
  end

  def de(node)
    return unless node.is_a?(Prism::CallNode)
    return [] if params?(node)
    return envelope_flexivel(node) if proprio?(node)

    base = de(node.receiver)
    base && descer(base, node)
  end

  # O nó é um envelope: `params.require(:x)` ou o `parameter_set(:x)` do CRM.
  def envelope?(node)
    return false unless node.is_a?(Prism::CallNode)
    return params?(node.receiver) if node.name == :require

    proprio?(node) && envelope_flexivel(node).present?
  end

  # Chamada a método do próprio controller (o que o `Leitor` segue).
  def proprio?(node)
    return false unless node.is_a?(Prism::CallNode) && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
    return false if node.name == :params

    Fontes.do_controller?(@klass.instance_method(node.name).source_location&.first.to_s)
  rescue NameError
    false
  end

  def params?(node)
    node.is_a?(Prism::CallNode) && node.name == :params && node.receiver.nil? && node.arguments.nil?
  end

  def literal(node)
    node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
  end

  def literais(node)
    chaves = (node.arguments&.arguments || []).map { |argumento| literal(argumento) }
    chaves if chaves.any? && chaves.none?(&:nil?)
  end

  private

  def descer(base, node)
    return base if node.name == :presence

    chaves = chaves_lidas(node)
    chaves && (base + chaves)
  end

  def chaves_lidas(node)
    case node.name
    when :require, :[], :fetch
      chave = literal(node.arguments&.arguments&.first)
      chave && [chave]
    when :dig then literais(node)
    end
  end

  # `parameter_set(:pipeline)` do CRM: `params[root_key].presence || params`.
  # O envelope é o argumento, e o corpo plano também serve.
  def envelope_flexivel(node)
    chave = literal(node.arguments&.arguments&.first)
    return unless chave && node.arguments.arguments.size == 1

    definicao = Fontes.definicao(@klass.instance_method(node.name))
    return unless definicao && aceita_plano?(definicao)

    @coleta.envelopes_flexiveis << chave
    [chave]
  end

  def aceita_plano?(definicao)
    pilha = [definicao.body].compact
    until pilha.empty?
      node = pilha.pop
      return true if node.is_a?(Prism::OrNode) && params?(node.right)

      pilha.concat(node.compact_child_nodes)
    end
    false
  end
end
