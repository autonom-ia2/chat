# O modelo do recurso e o que ele diz de cada campo (#900): tipo pela coluna,
# obrigatório, valores válidos, faixa e padrão.
#
# Só entra o que a reflexão do ActiveRecord dá com certeza. Validação escrita
# como método (`validate :json_conditions_format`) não é introspectável e fica
# de fora — quem recusa é o servidor, na hora. Lambda de validação nunca é
# chamada: `options[:in]` só vale quando já é lista ou faixa fixa, e
# `options[:message]` nem é lido.
module Autonomia::Guide::Formatos::Modelo
  LISTA_GRANDE = 40
  EXEMPLOS = 5
  TIPOS = {
    string: 'string', text: 'string', citext: 'string', uuid: 'string', integer: 'inteiro', bigint: 'inteiro',
    float: 'numero', decimal: 'numero', boolean: 'booleano', json: 'json', jsonb: 'json', date: 'data',
    datetime: 'data_hora', time: 'hora'
  }.freeze
  FAIXAS = {
    greater_than_or_equal_to: 'min', less_than_or_equal_to: 'max', greater_than: 'maior_que', less_than: 'menor_que',
    equal_to: 'igual_a'
  }.freeze
  TAMANHOS = { minimum: 'min_caracteres', maximum: 'max_caracteres', is: 'caracteres' }.freeze

  module_function

  # O modelo de um controller: o do `wrap_parameters` (deduzido do nome do
  # controller) e, quando ele não acha — o CRM mora em namespace —, o que a
  # action usa (`Current.account.crm_cards`, `policy_scope(::Crm::Card)`). O
  # que bate com o envelope ganha; depois, o da própria action.
  def resolver(klass, coleta)
    wrapper = klass._wrapper_options.model
    return wrapper if wrapper.is_a?(Class) && wrapper < ActiveRecord::Base

    citado(coleta)
  rescue NameError
    nil
  end

  # Primeiro o modelo onde a action grava o corpo (`Destinos`); depois o que
  # bate com o envelope; depois o que a própria action cita. O citado só num
  # `before_action` é o que ele busca, não onde o corpo vai: o
  # `fetch_conversation` do Linear daria à issue o enum de prioridade e os ids
  # inteiros da conversa, e o Linear quer 0 a 4 e UUID.
  def citado(coleta)
    candidatos = coleta.modelos
    envelopes = envelopes(coleta)
    escolhido = candidatos.find { |candidato| envelopes.include?(candidato.modelo.model_name.element) }
    coleta.destino || (escolhido || candidatos.find(&:da_action))&.modelo
  end

  def envelopes(coleta)
    coleta.permits.select(&:envelope).map { |permit| permit.caminho.first } + coleta.envelopes_flexiveis
  end

  # O que o modelo diz de um campo, já no formato do JSON.
  def anotar(modelo, nome, campo, criando:)
    return {} unless modelo

    {
      'tipo' => tipo(modelo, nome, campo),
      'padrao' => padrao(modelo, nome)
    }.compact.merge(validacoes(modelo, nome, criando)).compact
  end

  def tipo(modelo, nome, campo)
    coluna = modelo.columns_hash[nome]
    case campo[:forma]
    when :lista then 'lista'
    when :livre then 'objeto_livre'
    when :aninhado then colecao?(modelo, nome, coluna) ? 'lista_de_objetos' : 'objeto'
    else tipo_escalar(modelo, nome, coluna)
    end
  end

  def tipo_escalar(modelo, nome, coluna)
    return 'lista' if coluna&.array
    return TIPOS[coluna.type] if coluna
    return 'lista' if nome.end_with?('_ids') && modelo.reflect_on_association(nome.delete_suffix('_ids').pluralize)

    nil
  end

  # `conditions: [...]` no `permit` aceita objeto e lista de objetos; quem
  # decide é o modelo. Associação `has_many` e coluna de array são lista. Em
  # coluna JSON o esquema não diz: nome no plural (`conditions`, `actions`) é
  # lista, no singular (`csat_config`) é objeto.
  def colecao?(modelo, nome, coluna)
    return true if modelo.reflect_on_association(nome)&.collection? || coluna&.array

    json?(coluna) && nome.pluralize == nome && nome.singularize != nome
  end

  def json?(coluna)
    coluna.present? && %i[json jsonb].include?(coluna.type)
  end

  # O padrão da coluna, quando diz algo (`false` diz; `''` e coluna JSON não).
  def padrao(modelo, nome)
    return if json?(modelo.columns_hash[nome])

    valor = modelo.column_defaults[nome]
    return if valor.nil? || valor.try(:empty?)

    valor.is_a?(BigDecimal) ? valor.to_f : valor
  end

  def validacoes(modelo, nome, criando)
    validadores(modelo, nome, criando).each_with_object(enum(modelo, nome)) do |validador, anotado|
      anotado.merge!(validacao(validador, criando)) { |_chave, atual, _nova| atual }
    end
  end

  # Os validadores do campo e, para chave estrangeira, os do `belongs_to`
  # (`pipeline_id` herda o "obrigatório" de `belongs_to :pipeline`).
  def validadores(modelo, nome, criando)
    associacao = modelo.reflect_on_all_associations(:belongs_to).find { |assoc| assoc.foreign_key.to_s == nome }
    lista = modelo.validators_on(nome.to_sym) + (associacao ? modelo.validators_on(associacao.name) : [])
    lista.select { |validador| no_contexto?(validador, criando) }
  end

  def no_contexto?(validador, criando)
    contextos = Array(validador.options[:on])
    contextos.empty? || contextos.include?(criando ? :create : :update)
  end

  def validacao(validador, criando)
    case validador
    when ActiveModel::Validations::PresenceValidator then presenca(validador, criando)
    when ActiveModel::Validations::InclusionValidator then inclusao(validador)
    when ActiveModel::Validations::NumericalityValidator then faixa(validador)
    when ActiveModel::Validations::LengthValidator then tamanho(validador)
    else {}
    end
  end

  # A presença que o modelo exige é do registro, não do corpo: entre os dois há
  # o que a action faz, e ela pode preencher o campo sozinha — o card tira o
  # título do contato, o ContactInboxBuilder gera o source_id. Por isso aqui
  # só informa (`pelo_modelo`); quem bloqueia é o `params.require` do código.
  def presenca(validador, criando)
    condicional = validador.options[:if] || validador.options[:unless]
    return { 'obrigatorio' => 'condicional' } if condicional

    criando ? { 'obrigatorio' => 'pelo_modelo' } : { 'nao_pode_ficar_vazio' => true }
  end

  def inclusao(validador)
    valores = validador.options[:in] || validador.options[:within]
    return faixa_fixa(valores) if valores.is_a?(Range) && valores.begin.is_a?(Numeric)
    return {} unless valores.is_a?(Array) || valores.is_a?(Set) || valores.is_a?(Range)

    um_de(valores.to_a)
  end

  def enum(modelo, nome)
    valores = modelo.defined_enums[nome]
    valores ? um_de(valores.keys).merge('tipo' => 'string') : {}
  end

  def um_de(valores)
    valores = valores.map { |valor| valor.is_a?(Symbol) ? valor.to_s : valor }
    return { 'um_de' => valores } if valores.size <= LISTA_GRANDE

    exemplos = valores.first(EXEMPLOS).join(', ')
    { 'um_de_resumo' => "#{valores.size} valores aceitos, por exemplo: #{exemplos}", 'valida_no_servidor' => true }
  end

  def faixa_fixa(faixa)
    { 'min' => faixa.begin, 'max' => faixa.end }.compact
  end

  def faixa(validador)
    anotado = FAIXAS.each_with_object({}) do |(opcao, chave), hash|
      valor = validador.options[opcao]
      hash[chave] = valor if valor.is_a?(Numeric)
    end
    validador.options[:only_integer] ? anotado.merge('tipo' => 'inteiro') : anotado
  end

  def tamanho(validador)
    anotado = TAMANHOS.each_with_object({}) do |(opcao, chave), hash|
      valor = validador.options[opcao]
      hash[chave] = valor if valor.is_a?(Integer)
    end
    faixa = validador.options[:in] || validador.options[:within]
    faixa.is_a?(Range) ? anotado.merge('min_caracteres' => faixa.begin, 'max_caracteres' => faixa.end).compact : anotado
  end
end
