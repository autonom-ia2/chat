# Lê, com o Prism, o que uma action faz com `params` (#900).
#
# Parte do método da action — e da cadeia de `super_method`, que é por onde
# chegam o `prepend_mod_with` do Enterprise e a herança — e desce nos métodos
# do próprio controller que ela chama. Não executa nada: o que o código não
# diz fica marcado como dinâmico, e o `Espiao` resolve depois.
#
# Chave de `params` que não é literal (`params[k]` no `params.each`,
# `params[root_key]` do CRM) é ignorada de propósito: não é nome de campo, e
# era o ruído do primeiro analisador.
class Autonomia::Guide::Formatos::Leitor
  Formatos = ::Autonomia::Guide::Formatos
  Coleta = Formatos::Coleta

  PROFUNDIDADE = 6
  LEITURAS = %i[[] fetch key? has_key?].freeze
  # `request.raw_post` fica de fora: o CRM o lê para a chave de idempotência,
  # não para tirar campo dele.
  DO_CORPO_CRU = %i[body request_parameters].freeze
  PARAMS_INTEIRO = %i[to_unsafe_h to_h to_hash permit!].freeze

  attr_reader :coleta

  def initialize(klass)
    @klass = klass
    @coleta = Coleta.new
    @caminhos = Formatos::Caminhos.new(klass, @coleta)
    @vistos = Set.new
  end

  def ler(nome, da_action: true, profundidade: 0)
    return self if profundidade > PROFUNDIDADE || !@vistos.add?(nome.to_sym)

    cadeia(nome).each_with_index do |metodo, indice|
      chama_super = percorrer(metodo, da_action, profundidade)
      fora_do_repositorio(metodo) if chama_super.nil? && indice.positive?
      break unless chama_super
    end
    self
  end

  private

  def cadeia(nome)
    metodo = @klass.instance_method(nome)
    lista = []
    while metodo
      lista << metodo
      metodo = metodo.super_method
    end
    lista
  rescue NameError
    []
  end

  # Lê o método e diz se ele chama `super` (nil quando ele não mora nos
  # controllers do repositório). A cadeia só desce enquanto há `super`: o
  # override que não chama esconde o de baixo.
  def percorrer(metodo, da_action, profundidade)
    definicao = Formatos::Fontes.definicao(metodo)
    return unless definicao

    @atual = { metodo: metodo, arquivo: metodo.source_location.first, da_action: da_action, profundidade: profundidade,
               escopo: Formatos::Locais.coletar(definicao.body, metodo.owner) }
    chama_super = false
    pilha = [definicao.body].compact
    until pilha.empty?
      node = pilha.pop
      chama_super ||= node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)
      examinar(node)
      pilha.concat(node.compact_child_nodes)
    end
    chama_super
  end

  # A action chegou, por `super`, em código de gem (o `create` do
  # `ActiveStorage::DirectUploadsController`): o que ela aceita não está aqui.
  def fora_do_repositorio(metodo)
    arquivo = metodo.source_location&.first
    @coleta.externos << metodo.owner.name if arquivo && Formatos::Fontes.relativo(arquivo) == arquivo
  end

  def examinar(node)
    return registrar_modelo(Formatos::ModelosCitados.da_constante(node, @atual[:metodo].owner)) if constante?(node)
    return unless node.is_a?(Prism::CallNode)

    atual = @atual
    registrar_por_nome(node)
    registrar_recurso(node)
    registrar_corpo_cru(node)
    registrar_repasse(node)
    registrar_modelo(Formatos::ModelosCitados.da_conta(node))
    seguir(node, atual)
    @atual = atual
  end

  def constante?(node)
    node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
  end

  def registrar_por_nome(node)
    case node.name
    when :permit then registrar_permit(node)
    when :permit! then registrar_permit_total(node)
    when :require then registrar_require(node)
    when :dig then registrar_leitura(node, @caminhos.literais(node))
    when *LEITURAS then registrar_leitura(node, @caminhos.literais(node)&.first(1))
    end
  end

  # `feature_enabled?('delayed_automations')`: o nome entra no `so_se`.
  def registrar_recurso(node)
    nome = primeiro_literal(node) if node.name == :feature_enabled?
    @coleta.recursos << nome if nome
  end

  def registrar_permit(node)
    base = @caminhos.de(node.receiver)
    return if base.nil?

    filtros = Formatos::Filtros.argumentos(node.arguments&.arguments || [], @atual[:escopo])
    @coleta.permits << Coleta::Permit.new(caminho: base, filtros: filtros, metodo: @atual[:metodo].name, dono: @atual[:metodo].owner,
                                          origem: origem(node), envelope: @caminhos.envelope?(node.receiver))
  end

  def registrar_permit_total(node)
    base = @caminhos.de(node.receiver)
    return if base.nil?
    return @coleta.totais << origem(node) if base.empty? || @caminhos.envelope?(node.receiver)

    @coleta.livres << Coleta::Leitura.new(caminho: base, origem: origem(node))
  end

  def registrar_require(node)
    chave = primeiro_literal(node)
    return unless chave && @caminhos.params?(node.receiver)

    @coleta.leituras << Coleta::Leitura.new(caminho: [chave], origem: origem(node), exigida: true)
  end

  def registrar_leitura(node, chaves)
    base = @caminhos.de(node.receiver)
    return if base.nil? || chaves.blank?

    @coleta.leituras << Coleta::Leitura.new(caminho: base + chaves, origem: origem(node), exigida: false)
  end

  def registrar_corpo_cru(node)
    return unless DO_CORPO_CRU.include?(node.name)
    return unless node.receiver.is_a?(Prism::CallNode) && node.receiver.name == :request && node.receiver.receiver.nil?

    @coleta.corpo_cru << origem(node)
  end

  # `params` inteiro entregue a outro objeto: os nomes aceitos passam a ser
  # decisão de quem recebe. Método do próprio controller não conta — ele é lido.
  def registrar_repasse(node)
    return if @caminhos.proprio?(node) || @caminhos.de(node.receiver)
    return unless argumentos(node).any? { |argumento| params_inteiro?(argumento) }

    @coleta.repasses << "#{node.receiver&.slice || 'self'}.#{node.name}".truncate(80)
  end

  def registrar_modelo(modelo)
    @coleta.modelos << Coleta::Candidato.new(modelo: modelo, da_action: @atual[:da_action]) if modelo
  end

  def seguir(node, atual)
    return unless @caminhos.proprio?(node)

    ler(node.name, da_action: atual[:da_action], profundidade: atual[:profundidade] + 1)
  end

  def params_inteiro?(node)
    @caminhos.params?(node) || (node.is_a?(Prism::CallNode) && PARAMS_INTEIRO.include?(node.name) && @caminhos.params?(node.receiver))
  end

  def argumentos(node)
    (node.arguments&.arguments || []).flat_map do |argumento|
      argumento.is_a?(Prism::KeywordHashNode) ? argumento.elements.filter_map { |par| par.try(:value) } : [argumento]
    end
  end

  def primeiro_literal(node)
    @caminhos.literal(node.arguments&.arguments&.first)
  end

  def origem(node)
    Formatos::Fontes.origem(@atual[:arquivo], node)
  end
end
