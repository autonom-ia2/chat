# Para onde vai o corpo de uma action (#900): o modelo que recebe o `permit`,
# como em `Current.account.teams.new(team_params)` ou `@stage.update!(stage_params)`.
#
# Quando o `wrap_parameters` não deduz o modelo, é deste destino que o formato
# tira tipo, enum e validação. O modelo que a action só consulta não serve: o
# `fetch_conversation` do Linear daria à issue a prioridade da conversa (low a
# urgent), e o Linear quer 0 a 4. A variável de instância se resolve no fim,
# porque quem a preenche é o `before_action`, lido depois da action.
module Autonomia::Guide::Formatos::Destinos
  Coleta = ::Autonomia::Guide::Formatos::Coleta
  Citados = ::Autonomia::Guide::Formatos::ModelosCitados
  GRAVAM = %i[new build create create! update update! assign_attributes].freeze
  HAS_ONE = %w[build_ create_].freeze

  module_function

  # `@stage = Current.account.crm_pipeline_stages.find(...)`: a variável passa
  # a apontar o modelo.
  def variavel(node, coleta, modulo)
    modelo = da_cadeia(node.value, modulo)
    coleta.variaveis[node.name] ||= modelo if modelo
  end

  # A chamada que grava o corpo num modelo; o montador fica anotado para o
  # destino só valer se ele for mesmo um `permit` (`Coleta#destino`).
  def registrar(node, coleta, caminhos, modulo)
    modelo = do_has_one(node)
    return unless modelo || (GRAVAM.include?(node.name) && node.receiver)

    montador = montador(node, caminhos)
    return unless montador

    destino = modelo ? Coleta::Destino.new(modelo: modelo, metodo: montador) : do_receptor(node.receiver, modulo, montador)
    coleta.destinos << destino if destino
  end

  # `@stage.update!(...)` aponta a variável, resolvida no fim; o resto, o
  # modelo da cadeia.
  def do_receptor(receptor, modulo, montador)
    return Coleta::Destino.new(variavel: receptor.name, metodo: montador) if receptor.is_a?(Prism::InstanceVariableReadNode)

    modelo = da_cadeia(receptor, modulo)
    Coleta::Destino.new(modelo: modelo, metodo: montador) if modelo
  end

  # O argumento que leva o corpo: o montador do controller
  # (`stage_params.merge(...)`) ou o `permit` ali mesmo (`:permit`).
  def montador(node, caminhos)
    (node.arguments&.arguments || []).each do |argumento|
      while argumento.is_a?(Prism::CallNode)
        return :permit if argumento.name == :permit
        return argumento.name if caminhos.proprio?(argumento)

        argumento = argumento.receiver
      end
    end
    nil
  end

  # `Current.account.build_saml_settings(...)`: o construtor do `has_one` da
  # conta grava no modelo da associação.
  def do_has_one(node)
    nome = node.name.to_s.delete_suffix('!')
    prefixo = HAS_ONE.find { |inicio| nome.start_with?(inicio) }
    return unless prefixo && Citados.conta?(node.receiver)

    associacao = Account.reflect_on_association(nome.delete_prefix(prefixo))
    associacao.klass if associacao&.macro == :has_one
  rescue NameError
    nil
  end

  # O modelo de uma cadeia: a associação da conta, a constante do modelo
  # (também a do `policy_scope(::Crm::PipelineStage)`), ou um dos lados de `a || b`.
  def da_cadeia(node, modulo)
    return da_cadeia(node.left, modulo) || da_cadeia(node.right, modulo) if node.is_a?(Prism::OrNode)

    while node.is_a?(Prism::CallNode)
      modelo = Citados.da_conta(node) || do_escopo(node, modulo)
      return modelo if modelo

      node = node.receiver
    end
    constante(node, modulo)
  end

  def do_escopo(node, modulo)
    constante(node.arguments&.arguments&.first, modulo) if node.name == :policy_scope && node.receiver.nil?
  end

  def constante(node, modulo)
    Citados.da_constante(node, modulo) if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
  end
end
