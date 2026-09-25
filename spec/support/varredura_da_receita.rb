require 'prism'

# A VARREDURA DAS GUARDAS DA RECEITA DE RAMO (chat#641, receita v3): regex e criação de mensagem, por AST (Prism).
#
# Por AST, e não por texto, pelo mesmo motivo de `VarreduraDeRecusas`: busca textual acusa comentário e string, e não
# acha o que importa. E a própria varredura não usa regex: a regra que ela guarda vale para ela.
#
# Cada achado tem uma identidade estável enquanto o código não mudar de lugar: o arquivo, onde ele está (a classe e o
# método, ou a constante) e o trecho. A linha vai junto só para quem lê a mensagem de erro.
module VarreduraDaReceita
  Achado = Struct.new(:arquivo, :onde, :tipo, :trecho, :linha) do
    def chave
      [arquivo, onde, tipo, trecho]
    end

    def to_s
      "#{arquivo}:#{linha}  #{onde}  #{tipo}  #{trecho}"
    end
  end

  module_function

  # Os .rb sob cada raiz (pasta, recursiva, ou arquivo), relativos à raiz do app, sem repetir.
  def arquivos(raizes)
    raizes.flat_map { |raiz| caminhos(raiz) }.map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.uniq.sort
  end

  def caminhos(raiz)
    absoluto = Rails.root.join(raiz).to_s
    return [absoluto] if absoluto.end_with?('.rb')

    Dir[File.join(absoluto, '**', '*.rb')]
  end

  def arvore(caminho)
    Prism.parse_file(Rails.root.join(caminho).to_s).value
  end

  # Percorre a árvore entregando cada nó e onde ele está: `::Classe#metodo`, ou `::Classe::CONSTANTE`.
  def cada_no(nodo, onde = '', &)
    return if nodo.nil?

    onde = onde_de(nodo, onde)
    yield(nodo, onde)
    nodo.compact_child_nodes.each { |filho| cada_no(filho, onde, &) }
  end

  def onde_de(nodo, onde)
    case nodo
    when Prism::ClassNode, Prism::ModuleNode then "#{onde.split('#').first}::#{nodo.constant_path.slice}"
    when Prism::DefNode then "#{onde.split('#').first}##{nodo.name}"
    when Prism::ConstantWriteNode then "#{onde}::#{nodo.name}"
    else onde
    end
  end

  # A primeira linha do trecho, curta: é identidade e mensagem, não cópia do código.
  def trecho(texto)
    texto.to_s.lines.first.to_s.strip[0, 120]
  end
end

# O QUE CONTA COMO USO DE REGEX (guarda 1).
module VarreduraDaReceita::Regex
  LITERAIS = [Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode, Prism::MatchLastLineNode,
              Prism::InterpolatedMatchLastLineNode].freeze
  # Casamento: todo `=~`, `!~`, `match` e `match?`. `String#match('x')` também compila regex.
  CASAMENTO = %i[=~ !~ match match?].freeze
  # Métodos de String e de Enumerable que aceitam um padrão como primeiro argumento. Com literal, o literal já conta;
  # aqui entra o padrão guardado numa constante de regex.
  COM_PADRAO = %i[gsub gsub! sub sub! scan split slice slice! [] index rindex start_with? partition rpartition === grep
                  grep_v].freeze
  # Capturas globais do último casamento: `$~`, `$1`.
  CAPTURAS = [Prism::BackReferenceReadNode, Prism::NumberedReferenceReadNode].freeze

  module_function

  # -> [Achado], de todos os arquivos juntos (a constante de regex pode estar num arquivo e o uso em outro).
  def usos(arquivos)
    arvores = arquivos.index_with { |caminho| VarreduraDaReceita.arvore(caminho) }
    constantes = arvores.values.flat_map { |raiz| constantes_de_regex(raiz) }.uniq
    arvores.flat_map { |caminho, raiz| usos_em(caminho, raiz, constantes) }
  end

  def usos_em(caminho, raiz, constantes)
    achados = []
    VarreduraDaReceita.cada_no(raiz) do |nodo, onde|
      tipo, trecho = classificar(nodo, constantes)
      achados << VarreduraDaReceita::Achado.new(caminho, onde, tipo, trecho, nodo.location.start_line) if tipo
    end
    achados
  end

  # -> [tipo, trecho] quando o nó usa regex, ou nil.
  def classificar(nodo, constantes)
    return ['literal', VarreduraDaReceita.trecho(nodo.slice)] if literal?(nodo)
    return ['captura', nodo.slice] if CAPTURAS.any? { |classe| nodo.is_a?(classe) }
    return ['when', VarreduraDaReceita.trecho(nodo.slice)] if when_com_constante?(nodo, constantes)

    nodo.is_a?(Prism::CallNode) ? classificar_chamada(nodo, constantes) : nil
  end

  def classificar_chamada(nodo, constantes)
    return ["Regexp.#{nodo.name}", VarreduraDaReceita.trecho(nodo.slice)] if sobre_regexp?(nodo)
    return [nodo.name.to_s, chamada(nodo)] if CASAMENTO.include?(nodo.name)
    return ["#{nodo.name}(constante)", chamada(nodo)] if COM_PADRAO.include?(nodo.name) && constante_de_regex?(primeiro(nodo), constantes)

    nil
  end

  def literal?(nodo)
    LITERAIS.any? { |classe| nodo.is_a?(classe) }
  end

  # `Regexp.new`, `Regexp.union`, `::Regexp.escape`, `Regexp.last_match`...
  def sobre_regexp?(nodo)
    receptor = nodo.receiver
    (receptor.is_a?(Prism::ConstantReadNode) || receptor.is_a?(Prism::ConstantPathNode)) && receptor.name == :Regexp
  end

  def when_com_constante?(nodo, constantes)
    nodo.is_a?(Prism::WhenNode) && nodo.conditions.any? { |condicao| constante_de_regex?(condicao, constantes) }
  end

  def primeiro(nodo)
    Array(nodo.arguments&.arguments).first
  end

  def constante_de_regex?(nodo, constantes)
    (nodo.is_a?(Prism::ConstantReadNode) || nodo.is_a?(Prism::ConstantPathNode)) && constantes.include?(nodo.name)
  end

  # O trecho de uma chamada sem o receptor encadeado (que muda com o código em volta): o receptor só entra quando é
  # uma constante, como `MARCADOR.match?(valor)`.
  def chamada(nodo)
    receptor = nodo.receiver
    prefixo = receptor.is_a?(Prism::ConstantReadNode) || receptor.is_a?(Prism::ConstantPathNode) ? "#{receptor.slice}." : ''
    VarreduraDaReceita.trecho("#{prefixo}#{nodo.name}(#{nodo.arguments&.slice})")
  end

  # `NOME = /x/`, `NOME = %r{x}.freeze`, `NOME = Regexp.union(...)` -> [:NOME]
  def constantes_de_regex(raiz)
    nomes = []
    VarreduraDaReceita.cada_no(raiz) do |nodo, _onde|
      nomes << nodo.name if nodo.is_a?(Prism::ConstantWriteNode) && regex?(sem_freeze(nodo.value))
    end
    nomes
  end

  def regex?(valor)
    literal?(valor) || (valor.is_a?(Prism::CallNode) && sobre_regexp?(valor))
  end

  # `X.freeze` -> `X`
  def sem_freeze(valor)
    valor = valor.receiver while valor.is_a?(Prism::CallNode) && valor.name == :freeze
    valor
  end
end

# ONDE UMA MENSAGEM NASCE (guarda 2): o `MessageBuilder` do Chatwoot, `messages.create/new/build` e `Message.create`.
module VarreduraDaReceita::Mensagem
  NA_COLECAO = %i[create create! new build].freeze
  NO_MODELO = %i[create create! new insert insert! insert_all insert_all! upsert upsert_all].freeze

  # Um ponto: onde está, e o que a chamada diz de `content:` e de `private:` (o nó do valor, ou nil sem a chave).
  Ponto = Struct.new(:arquivo, :onde, :linha, :content, :private) do
    def chave
      "#{arquivo}#{onde}"
    end

    def to_s
      "#{arquivo}:#{linha}  #{onde}"
    end
  end

  module_function

  def pontos(arquivos)
    arquivos.flat_map do |caminho|
      lista = []
      VarreduraDaReceita.cada_no(VarreduraDaReceita.arvore(caminho)) do |nodo, onde|
        lista << ponto(caminho, onde, nodo) if cria_mensagem?(nodo)
      end
      lista
    end
  end

  def cria_mensagem?(nodo)
    return false unless nodo.is_a?(Prism::CallNode)

    builder?(nodo) || na_colecao?(nodo) || no_modelo?(nodo) || nodo.name.to_s.include?('create_message')
  end

  def builder?(nodo)
    nodo.name == :new && constante?(nodo.receiver, :MessageBuilder)
  end

  # `conversation.messages.create!(...)`, `@conversation.messages.new(...)`
  def na_colecao?(nodo)
    NA_COLECAO.include?(nodo.name) && nodo.receiver.is_a?(Prism::CallNode) && nodo.receiver.name == :messages
  end

  def no_modelo?(nodo)
    NO_MODELO.include?(nodo.name) && constante?(nodo.receiver, :Message)
  end

  def constante?(nodo, nome)
    (nodo.is_a?(Prism::ConstantReadNode) || nodo.is_a?(Prism::ConstantPathNode)) && nodo.name == nome
  end

  def ponto(caminho, onde, nodo)
    pares = pares(nodo)
    Ponto.new(caminho, onde, nodo.location.start_line, pares[:content], pares[:private])
  end

  # Os pares `chave: valor` da mensagem: no `MessageBuilder`, dentro do `ActionController::Parameters.new(...)`; nos
  # outros, nos argumentos da própria chamada.
  def pares(nodo)
    hashes(nodo).flat_map(&:elements).each_with_object({}) do |elemento, pares|
      next unless elemento.is_a?(Prism::AssocNode) && elemento.key.is_a?(Prism::SymbolNode)

      pares[elemento.key.unescaped.to_sym] = elemento.value
    end
  end

  def hashes(nodo)
    argumentos = argumentos(nodo)
    parametros = argumentos.select { |arg| arg.is_a?(Prism::CallNode) && arg.name == :new }
    (argumentos + parametros.flat_map { |arg| argumentos(arg) }).select { |arg| hash?(arg) }
  end

  def argumentos(nodo)
    Array(nodo.arguments&.arguments)
  end

  def hash?(nodo)
    nodo.is_a?(Prism::HashNode) || nodo.is_a?(Prism::KeywordHashNode)
  end
end
