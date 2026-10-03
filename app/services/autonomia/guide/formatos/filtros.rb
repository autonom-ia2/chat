# Os argumentos de um `permit`, lidos do código (Prism) ou capturados em
# execução, viram uma árvore de campos (#900).
#
# A árvore tem quatro formas, as mesmas que o strong params entende:
# - `:escalar` — `:name`;
# - `:lista` — `permissions: []`, lista de valores soltos;
# - `:livre` — `metadata: {}`, objeto com qualquer chave;
# - `:aninhado` — `csat_config: [...]`, objeto (ou lista de objetos) com os
#   campos de dentro. Qual dos dois, só o modelo diz; quem decide é `Modelo`.
#
# O que o código não deixa saber sem executar — splat de método, valor
# calculado — vira `Dinamico`, e quem lê a árvore sabe que ela está
# incompleta. Constante se resolve aqui mesmo, por reflexão (`working_hours:
# Inbox::OFFISABLE_ATTRS`), e variável local montada no próprio método também
# (`Locais`).
module Autonomia::Guide::Formatos::Filtros
  Dinamico = Struct.new(:trecho)
  # Onde o nó mora: o módulo resolve constante; `locais`, as variáveis do método.
  Escopo = Struct.new(:modulo, :locais)

  module_function

  # Nó do Prism → o mesmo valor Ruby que o `permit` receberia, com `Dinamico`
  # onde o código não diz.
  def do_codigo(node, escopo)
    case node
    when Prism::SymbolNode, Prism::StringNode then node.unescaped
    when Prism::ArrayNode then node.elements.flat_map { |item| espalhar(item, escopo) }
    when Prism::HashNode, Prism::KeywordHashNode then par_a_par(node, escopo)
    else referencia(node, escopo)
    end
  end

  # Constante e variável local: o valor vem de fora do próprio nó.
  def referencia(node, escopo)
    case node
    when Prism::ConstantReadNode, Prism::ConstantPathNode then constante(node, escopo)
    when Prism::LocalVariableReadNode then escopo.locais.fetch(node.name) { Dinamico.new(node.slice) }
    when Prism::CallNode then lista_do_metodo(node, escopo)
    else Dinamico.new(node.slice)
    end
  end

  # `slice(*account_user_attributes)`: método do controller, sem argumento,
  # cujo corpo é só uma lista literal, se lê como a constante. Qualquer outra
  # coisa fica para o `Espiao`, que executa.
  def lista_do_metodo(node, escopo)
    lista = lista_literal(node, escopo.modulo) if node.receiver.nil? && node.arguments.nil?
    lista ? do_codigo(lista, Escopo.new(escopo.modulo, {})) : Dinamico.new(node.slice)
  end

  def lista_literal(node, modulo)
    corpo = ::Autonomia::Guide::Formatos::Fontes.definicao(modulo.instance_method(node.name))&.body
    corpo = corpo.body.first if corpo.is_a?(Prism::StatementsNode) && corpo.body.size == 1
    corpo if corpo.is_a?(Prism::ArrayNode)
  rescue NameError
    nil
  end

  def argumentos(nodes, escopo)
    nodes.flat_map { |node| espalhar(node, escopo) }
  end

  def espalhar(node, escopo)
    return [do_codigo(node, escopo)] unless node.is_a?(Prism::SplatNode)

    valor = node.expression && do_codigo(node.expression, escopo)
    valor.is_a?(Array) ? valor : [Dinamico.new(node.slice)]
  end

  def par_a_par(node, escopo)
    node.elements.each_with_object({}) do |elemento, hash|
      next hash[Dinamico.new(elemento.slice)] = nil unless elemento.is_a?(Prism::AssocNode)

      chave = do_codigo(elemento.key, escopo)
      hash[chave.is_a?(Dinamico) ? chave : chave.to_s] = do_codigo(elemento.value, escopo)
    end
  end

  def constante(node, escopo)
    valor = escopo.modulo.const_get(node.slice.delete_prefix('::'))
    valor.is_a?(Array) || valor.is_a?(Hash) ? normalizar_valor(valor) : Dinamico.new(node.slice)
  rescue NameError
    Dinamico.new(node.slice)
  end

  def normalizar_valor(valor)
    case valor
    when Array then valor.map { |item| normalizar_valor(item) }
    when Hash then valor.to_h { |chave, item| [chave.to_s, normalizar_valor(item)] }
    when Symbol then valor.to_s
    else valor
    end
  end

  # Lista de filtros (como `permit(*filtros)`) → { 'campo' => { forma:, campos: } }.
  # Achatada como o próprio `permit` faz: `permit(allowed_agent_params)` recebe
  # a lista inteira num argumento só, e cada item dela é um campo.
  def arvore(filtros)
    Array(filtros).flatten.each_with_object({}) do |filtro, campos|
      case filtro
      when Hash then filtro.each { |chave, valor| campos[chave.is_a?(Dinamico) ? chave : chave.to_s] = forma(valor) }
      when Dinamico then campos[filtro] = { forma: :dinamico }
      else campos[filtro.to_s] ||= { forma: :escalar }
      end
    end
  end

  def forma(valor)
    return { forma: :dinamico } if valor.is_a?(Dinamico)
    return { forma: :lista } if valor == []
    return { forma: :livre } if valor == {}
    return { forma: :aninhado, campos: arvore(valor) } if valor.is_a?(Array)
    return { forma: :aninhado, campos: arvore([valor]) } if valor.is_a?(Hash)

    { forma: :escalar }
  end

  def dinamica?(arvore)
    arvore.any? { |chave, campo| chave.is_a?(Dinamico) || campo[:forma] == :dinamico || dinamica?(campo[:campos] || {}) }
  end

  # Junta duas árvores do mesmo lugar. Forma mais rica ganha: o `permit` diz
  # `conditions: [...]` e o `params[:conditions]` cru só diz que existe.
  def juntar(base, outra)
    outra.each_with_object(base.dup) do |(chave, campo), junta|
      atual = junta[chave]
      next junta[chave] = campo if atual.nil?

      junta[chave] = escolher(atual, campo).merge(exigida: atual[:exigida] || campo[:exigida]).compact
    end
  end

  def escolher(atual, campo)
    if atual[:forma] == :aninhado && campo[:forma] == :aninhado
      atual.merge(campos: juntar(atual[:campos] || {}, campo[:campos] || {}), cru: atual[:cru] && campo[:cru])
    else
      riqueza(campo) > riqueza(atual) ? campo : atual
    end
  end

  # Leitura crua só diz que o campo existe; o `permit` diz o que ele aceita.
  def riqueza(campo)
    return 0 if campo[:forma] == :dinamico
    return 3 unless campo[:forma] == :escalar

    campo[:cru] ? 1 : 2
  end
end
