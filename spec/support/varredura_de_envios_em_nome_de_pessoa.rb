require 'prism'

# VARREDURA DOS ENVIOS EM NOME DE PESSOA (#1669), por AST (Prism), nunca por texto. Usada pela guarda
# `varredura_de_envios_em_nome_de_pessoa_spec`.
#
# O `PessoaDaEquipe.da_pessoa?` decide quem é PESSOA pelo remetente User, e tira os envios automáticos gravados em nome
# dela pela MARCA em `content_attributes`/`additional_attributes`. Um envio automático novo sem marca faria a IA ler o
# robô como pessoa (moldura) e calar à toa. Aqui se acha cada criação de mensagem com remetente e se cobra a marca.
#
# ENVIO COM REMETENTE:
#   (A) `Messages::MessageBuilder.new(remetente, ...)` / `Autonomia::LiteralMessageBuilder.new(remetente, ...)` com o 1º
#       argumento diferente de `nil`, ou com `sender_type:` nos parâmetros diferente de nil e de 'AgentBot';
#   (B) `create`/`create!`/`new`/`build` sobre `messages`/`Message` com `sender:` não-nil, ou `sender_type:` diferente
#       de nil e de 'AgentBot'.
# ENVIO A REVISAR: (B) cujos atributos não são hash literal (variável, chamada, `**attrs`): o remetente não é visível,
# então não passa calado — tem de estar em REVISADOS.
# MARCA: só vale como chave do valor de `content_attributes:`/`additional_attributes:`, seguindo variável local e
# método do mesmo módulo/classe chamado sem receptor (um nível de cada vez, sem laço).
module VarreduraDeEnviosEmNomeDePessoa
  RAIZES = %w[app lib enterprise/app].freeze
  BUILDERS = %w[Messages::MessageBuilder Autonomia::LiteralMessageBuilder].freeze
  CRIADORES = %i[create create! new build].freeze
  CHAVES_DE_ATRIBUTOS = %w[content_attributes additional_attributes].freeze
  REMETENTES_DE_ROBO = [nil, 'AgentBot'].freeze

  Envio = Struct.new(:arquivo, :linha, :dono, :metodo, :tipo, :chamada, keyword_init: true) do
    def id
      "#{arquivo}##{dono}##{metodo}"
    end
  end

  # Um método do arquivo, com o módulo/classe dono: `Crm::FollowUps::MessageSender#create_session_message`.
  Metodo = Struct.new(:dono, :nome, :corpo)

  module_function

  def marcas
    ::Autonomia::Agents::Operate::PessoaDaEquipe::MARCAS_DE_ENVIO_AUTOMATICO +
      ::Autonomia::Agents::Operate::PessoaDaEquipe::MARCAS_DE_CAMPANHA
  end

  def arquivos
    RAIZES.flat_map { |raiz| Dir[Rails.root.join(raiz, '**', '*.rb').to_s] }
          .map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.sort
  end

  def arvore_de(arquivo)
    Prism.parse_file(Rails.root.join(arquivo).to_s).value
  end

  # Percorre a árvore entregando cada nó com o dono (módulo/classe) e o método que o contém.
  def cada_no(nodo, dono = [], metodo = nil, &)
    return if nodo.nil?

    dono += [nodo.constant_path.slice] if nodo.is_a?(Prism::ClassNode) || nodo.is_a?(Prism::ModuleNode)
    metodo = nodo.name if nodo.is_a?(Prism::DefNode)
    yield(nodo, dono.join('::'), metodo)
    nodo.compact_child_nodes.each { |filho| cada_no(filho, dono, metodo, &) }
  end

  def argumentos(nodo)
    nodo.respond_to?(:arguments) ? Array(nodo.arguments&.arguments) : []
  end

  def chave(elemento)
    return unless elemento.is_a?(Prism::AssocNode)

    elemento.key.unescaped if elemento.key.is_a?(Prism::SymbolNode) || elemento.key.is_a?(Prism::StringNode)
  end

  def hashes(nodo)
    argumentos(nodo).select { |arg| arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode) }
  end

  def elementos(nodo)
    hashes(nodo).flat_map(&:elements)
  end

  def valor_de(lista, nome)
    lista.find { |elemento| chave(elemento) == nome }&.value
  end

  def texto(nodo)
    nodo.unescaped if nodo.is_a?(Prism::StringNode) || nodo.is_a?(Prism::SymbolNode)
  end

  # `sender_type:` que não é de robô: diferente de nil e de 'AgentBot' (uma variável também conta).
  def tipo_de_pessoa?(lista)
    valor = valor_de(lista, 'sender_type')
    return false if valor.nil? || valor.is_a?(Prism::NilNode)

    REMETENTES_DE_ROBO.exclude?(texto(valor))
  end

  def builder?(nodo)
    nodo.name == :new && nodo.receiver && BUILDERS.include?(nodo.receiver.slice.delete_prefix('::'))
  end

  # Parâmetros literais do builder (3º argumento, `ActionController::Parameters.new(...)` ou hash).
  def parametros_do_builder(nodo)
    terceiro = argumentos(nodo)[2]
    terceiro = argumentos(terceiro).first if terceiro.is_a?(Prism::CallNode) && terceiro.name == :new
    terceiro.respond_to?(:elements) ? terceiro.elements : []
  end

  def builder_com_remetente?(nodo)
    !argumentos(nodo).first.is_a?(Prism::NilNode) || tipo_de_pessoa?(parametros_do_builder(nodo))
  end

  def sobre_mensagens?(nodo)
    return false unless CRIADORES.include?(nodo.name) && nodo.receiver

    alvo = nodo.receiver.slice.delete_prefix('::')
    alvo == 'Message' || alvo.end_with?('messages')
  end

  def dinamico?(nodo)
    lista = argumentos(nodo)
    return false if lista.empty?

    lista.any? { |arg| !(arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode)) } ||
      elementos(nodo).any?(Prism::AssocSplatNode)
  end

  def criacao_com_remetente?(nodo)
    lista = elementos(nodo)
    remetente = valor_de(lista, 'sender')
    (remetente && !remetente.is_a?(Prism::NilNode)) || tipo_de_pessoa?(lista)
  end

  # -> :com_remetente, :revisar ou nil
  def tipo_do_envio(nodo)
    return unless nodo.is_a?(Prism::CallNode)
    return (:com_remetente if builder_com_remetente?(nodo)) if builder?(nodo)
    return unless sobre_mensagens?(nodo)
    return :com_remetente if criacao_com_remetente?(nodo)

    :revisar if dinamico?(nodo)
  end

  def envios_em(arvore, arquivo)
    lista = []
    cada_no(arvore) do |nodo, dono, metodo|
      tipo = tipo_do_envio(nodo)
      next if tipo.nil?

      lista << Envio.new(arquivo: arquivo, linha: nodo.location.start_line, dono: dono, metodo: metodo, tipo: tipo,
                         chamada: nodo)
    end
    lista
  end

  def envios
    arquivos.flat_map { |arquivo| envios_em(arvore_de(arquivo), arquivo) }
  end
end
