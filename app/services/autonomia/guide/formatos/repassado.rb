# O que uma classe nossa lê do `params` que o controller entregou inteiro a ela (#942).
#
# A leitura de conversas não lê `params` no controller: entrega tudo ao `ConversationFinder`, e é ele
# quem decide que `status`, `labels` e `q` existem. Aqui se lê essa classe, sem executar nada: em que
# variável o `initialize` guarda o argumento, e cada `@params[:x]` (ou `params[:x]`, pelo leitor da
# variável) nos métodos dela.
#
# Só vale quando TODO uso da variável é leitura de chave literal. Entregue inteira a outro objeto,
# percorrida ou lida com chave calculada, a lista não é confiável: devolve nil, e quem chamou não
# recusa nada.
module Autonomia::Guide::Formatos::Repassado
  Fontes = ::Autonomia::Guide::Formatos::Fontes
  LEITURAS = %i[[] fetch key? has_key? dig].freeze

  module_function

  # As chaves lidas, ou nil quando não dá para saber.
  def chaves(classe, posicao)
    variavel = guardado_em(classe, posicao)
    return unless variavel

    leitor = leitor_de(classe, variavel)
    usos = definicoes(classe).map { |corpo| usos(corpo, variavel, leitor) }
    usos.flat_map(&:first).uniq.sort if usos.none?(&:last)
  end

  # O método que devolve a variável (`attr_reader :params`), quando a classe tem.
  def leitor_de(classe, variavel)
    nome = variavel.to_s.delete_prefix('@').to_sym
    nome if classe.method_defined?(nome) || classe.private_method_defined?(nome)
  end

  # A variável de instância que recebe o argumento da posição: `@params = params`.
  def guardado_em(classe, posicao)
    inicio = classe.instance_method(:initialize)
    tipo, nome = inicio.parameters[posicao]
    return unless %i[req opt].include?(tipo)

    corpo = definicao(inicio)
    return unless corpo

    atribuicao = nos(corpo).find do |node|
      node.is_a?(Prism::InstanceVariableWriteNode) && node.value.is_a?(Prism::LocalVariableReadNode) && node.value.name == nome
    end
    atribuicao&.name
  end

  # O corpo de cada método da classe (e do que ela inclui ou recebe por prepend) que mora no repositório.
  def definicoes(classe)
    classe.ancestors.flat_map do |modulo|
      (modulo.instance_methods(false) + modulo.private_instance_methods(false)).filter_map do |nome|
        definicao(modulo.instance_method(nome))
      end
    end
  end

  def definicao(metodo)
    arquivo, linha = metodo.source_location
    return unless arquivo && File.file?(arquivo) && Fontes.do_repositorio?(arquivo)

    Fontes.definicoes(arquivo)[[linha, metodo.name]]&.body
  end

  # [chaves lidas, algum uso que não é leitura de chave literal?]
  def usos(corpo, variavel, leitor)
    todos = nos(corpo)
    referencias = todos.select { |node| referencia?(node, variavel, leitor) }
    lidas = todos.filter_map { |node| leitura(node, variavel, leitor) }
    [lidas.map(&:last), referencias.size > lidas.size]
  end

  # [nó da referência, chave] quando o nó lê uma chave literal da variável.
  def leitura(node, variavel, leitor)
    return unless node.is_a?(Prism::CallNode) && LEITURAS.include?(node.name) && referencia?(node.receiver, variavel, leitor)

    chave = literal(node.arguments&.arguments&.first)
    [node.receiver, chave] if chave
  end

  def literal(node)
    node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
  end

  def referencia?(node, variavel, leitor)
    return node.name == variavel if node.is_a?(Prism::InstanceVariableReadNode)

    leitor && node.is_a?(Prism::CallNode) && node.name == leitor && node.receiver.nil? && node.arguments.nil?
  end

  def nos(corpo)
    pilha = [corpo].compact
    todos = []
    until pilha.empty?
      node = pilha.pop
      todos << node
      pilha.concat(node.compact_child_nodes)
    end
    todos
  end
end
