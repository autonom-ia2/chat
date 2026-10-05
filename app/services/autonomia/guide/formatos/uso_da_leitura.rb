# O tipo de uma leitura crua (`params[:x]`) pelo que o código faz com ela (#932).
#
# O modelo do recurso não tem coluna para tudo o que a action lê: `params[:user_ids]`,
# `params[:force]`. Sem tipo, o Guia mandava o valor no formato que achava. O uso diz: o que vira
# `.to_i` é número inteiro, o que passa por `Boolean.new.cast` é true/false, o que é percorrido com
# `.each` é lista. Só a conversão escrita no código conta; nada é executado.
#
# Leitura que vai inteira para outro objeto (`Servico.new(x: params[:x])`) não tem uso aqui: o motivo
# fica registrado (`repasses`), e o relatório mostra quem decide.
module Autonomia::Guide::Formatos::UsoDaLeitura
  CONVERSOES = {
    to_i: 'inteiro', to_f: 'numero', to_d: 'numero', to_sym: 'string', split: 'string', strip: 'string',
    downcase: 'string', upcase: 'string', each: 'lista', map: 'lista', each_with_index: 'lista', filter_map: 'lista',
    to_a: 'lista', first: 'lista', compact: 'lista', uniq: 'lista', include?: 'lista', any?: 'lista', to_s: 'string',
    original_filename: 'arquivo', content_type: 'arquivo', tempfile: 'arquivo'
  }.freeze
  # Conversão do Kernel: `Integer(params[:x])`, `Array(params[:x])`.
  FUNCOES = { Integer: 'inteiro', Float: 'numero', Array: 'lista', String: 'string' }.freeze
  BOOLEANOS = %w[true false 1 0].freeze
  # [método, fim do receptor, tipo do argumento].
  RECEPTORES = [[:wrap, 'Array', 'lista'], [:cast, 'Boolean.new', 'booleano'], [:attach, '', 'arquivo']].freeze

  module_function

  # [caminho, tipo] quando o nó converte uma leitura crua; nil se não. `apelidos`: a variável local que
  # recebeu a leitura (`file = params[:file]`) conta como ela.
  def tipo(node, caminhos, apelidos = {})
    tipo, alvo = uso(node)
    caminho = tipo && lido(alvo, caminhos, apelidos)
    [caminho, tipo] if caminho.present?
  end

  def lido(node, caminhos, apelidos)
    node.is_a?(Prism::LocalVariableReadNode) ? apelidos[node.name] : caminhos.de(node)
  end

  # A variável local que recebe uma leitura crua inteira, em todo o método: nome => caminho.
  def apelidos(corpo, caminhos)
    pilha = [corpo].compact
    achados = {}
    until pilha.empty?
      node = pilha.pop
      caminho = node.is_a?(Prism::LocalVariableWriteNode) ? caminhos.de(node.value) : nil
      achados[node.name] = caminho if caminho.present?
      pilha.concat(node.compact_child_nodes)
    end
    achados
  end

  def uso(node)
    case node
    when Prism::CallNode then conversao(node)
    when Prism::OrNode then padrao(node)
    when Prism::InterpolatedStringNode then interpolado(node)
    end
  end

  # `params[:page] || 1`: o padrão diz o tipo.
  def padrao(node)
    return ['inteiro', node.left] if node.right.is_a?(Prism::IntegerNode)

    ['string', node.left] if node.right.is_a?(Prism::StringNode)
  end

  # "...#{params[:x]}...": vira texto.
  def interpolado(node)
    parte = node.parts.find { |item| item.is_a?(Prism::EmbeddedStatementsNode) }
    ['string', parte.statements&.body&.first] if parte
  end

  # [[caminho, quem recebe]] para cada leitura crua passada como argumento a outro objeto.
  def repasses(node, caminhos)
    return [] unless node.is_a?(Prism::CallNode) && node.receiver

    argumentos(node).filter_map do |argumento|
      caminho = caminhos.de(argumento) if argumento.is_a?(Prism::CallNode)
      [caminho, "#{node.receiver.slice}.#{node.name}".truncate(60)] if caminho.present?
    end
  end

  def conversao(node)
    return [CONVERSOES[node.name], node.receiver] if node.receiver && CONVERSOES.key?(node.name)

    tipo = do_argumento(node)
    tipo ? [tipo, primeiro(node)] : comparacao(node)
  end

  # A leitura vai como argumento de quem diz o tipo: `Integer(x)`, `Array.wrap(x)`, `Boolean.new.cast(x)`, `attach(x)`.
  def do_argumento(node)
    return FUNCOES[node.name] if node.receiver.nil?

    RECEPTORES.find { |nome, receptor, _tipo| node.name == nome && node.receiver.slice.end_with?(receptor) }&.last
  end

  # `params[:x] == 'true'` é true/false; `params[:x] == 3`, número.
  def comparacao(node)
    return unless %i[== !=].include?(node.name)

    outro = primeiro(node)
    return ['booleano', node.receiver] if outro.is_a?(Prism::StringNode) && BOOLEANOS.include?(outro.unescaped)

    return ['inteiro', node.receiver] if outro.is_a?(Prism::IntegerNode)

    ['string', node.receiver] if outro.is_a?(Prism::StringNode)
  end

  def primeiro(node)
    node.arguments&.arguments&.first
  end

  def argumentos(node)
    (node.arguments&.arguments || []).flat_map do |argumento|
      argumento.is_a?(Prism::KeywordHashNode) ? argumento.elements.filter_map { |par| par.try(:value) } : [argumento]
    end
  end
end
