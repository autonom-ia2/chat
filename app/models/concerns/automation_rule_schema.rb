# A regra interna das colunas `conditions` e `actions` de AutomationRule, como esquema JSON (#932).
#
# Antes ela morava em métodos de validação escritos à mão, que só conferiam o
# nome: a chave inventada, o id em texto que o motor compara com número e o parâmetro na forma errada
# gravavam e não faziam nada. O esquema diz o que o motor lê de verdade, e o Guia o lê para montar a
# regra certa de primeira (`Autonomia::Guide::Formatos::Esquemas`).
#
# Cada ação tem um ramo (`ramo` por `action_name`) com o `action_params` que o método dela no
# `AutomationRules::ActionService` lê. O spec de paridade falha se uma ação do motor ficar sem ramo.
# `x-sem-volta` marca a ação que sai da plataforma (mensagem, e-mail, webhook): a regra que a usa
# pede confirmação no Guia.
class AutomationRuleSchema
  include JsonSchemaBlocos

  QUERY_OPERATORS = ['AND', 'OR', 'and', 'or', '', nil].freeze
  TIPOS_DE_ATRIBUTO = %w[conversation_attribute contact_attribute].freeze
  SECOES = { 'conversations' => Conversation, 'contacts' => Contact, 'messages' => Message }.freeze
  MUDOU = 'attribute_changed'.freeze

  # Quando a regra roda: os eventos que o AutomationRuleListener escuta, com o que cada um faz de verdade.
  # Só descreve (a fábrica do upstream grava evento que não existe); quem lê é o Guia.
  EVENTOS = {
    'conversation_created' => 'uma vez, quando a conversa nasce',
    'conversation_opened' => 'quando a conversa volta para aberta',
    'conversation_resolved' => 'uma vez, quando a conversa é resolvida — é o evento de "ao resolver"',
    'conversation_updated' => 'a cada mudança na conversa (status, etiqueta, responsável): repete; não use para "ao resolver"',
    'message_created' => 'a cada mensagem nova, do cliente ou da equipe; com message_type incoming, só a do cliente'
  }.freeze
  # O que o motor faz de verdade com a condição, quando não é óbvio pelo nome.
  NOTAS = {
    'content' => ' Casa palavra solta no texto: "não quero cancelar" casa com "cancelar". Não serve para entender a ' \
                 "intenção do cliente; para isso a ação #{Autonomia::Decisores::PASSO}."
  }.freeze
  # "Se em N minutos ainda…": o que o motor faz com o atraso (#939 — sem isto o Guia não sabia a unidade).
  ATRASO = {
    'type' => %w[integer null], 'minimum' => AutomationRule::EXECUTION_DELAY_RANGE.min,
    'maximum' => AutomationRule::EXECUTION_DELAY_RANGE.max,
    'description' => "Minutos de espera antes de agir (#{AutomationRule::EXECUTION_DELAY_RANGE.min} a " \
                     "#{AutomationRule::EXECUTION_DELAY_RANGE.max}, até 30 dias); vazio age na hora. Na hora de agir a " \
                     'plataforma confere as condições de novo e desiste se não valem mais. Com eventos de conversa ' \
                     'só valem condições de status e caixa; com message_created, todas menos attribute_changed. ' \
                     'Precisa do recurso de atraso ligado na conta.'
  }.freeze
  EVENTO = { 'type' => 'string', 'examples' => EVENTOS.keys,
             'description' => "Quando a regra roda. #{EVENTOS.map { |nome, quando| "#{nome}: #{quando}" }.join('. ')}." }.freeze

  def self.actions(regra)
    new(regra).actions
  end

  def self.conditions(regra)
    new(regra).conditions
  end

  # Os operadores de cada filtro, lidos uma vez: a regra valida a cada gravação.
  def self.filtros
    @filtros ||= YAML.safe_load(Rails.root.join('lib/filters/filter_keys.yml').read).freeze
  end

  # Sem regra, o esquema geral: atributo personalizado vale qualquer chave da conta.
  def initialize(regra)
    @regra = regra || AutomationRule.new
    @conta = regra&.account
  end

  def actions
    nomes = @regra.actions_attributes.uniq
    acoes(nomes, nomes.filter_map { |nome| ramo_da_acao(nome) }, 'O que a regra faz, na ordem, quando as condições batem.')
  end

  def conditions
    item = { 'type' => 'object', 'required' => %w[attribute_key filter_operator], 'additionalProperties' => false,
             'properties' => propriedades_da_condicao, 'allOf' => ramos_das_condicoes }
    lista(item, descricao: 'Quando a regra roda. Cada condição liga na seguinte pelo query_operator.')
  end

  # O `action_params` de cada ação, com o que o motor faz com ele.
  def parametros
    AutomationRuleSchema::Acoes.parametros
  end

  private

  def ramo_da_acao(nome)
    parametro, descricao = parametros[nome]
    return unless parametro

    extras = Acoes::SEM_VOLTA.include?(nome) ? { 'x-sem-volta' => true } : {}
    ramo('action_name', nome, { 'properties' => { 'action_params' => parametro } }, descricao, extras)
  end

  def padrao
    @padrao ||= @regra.conditions_attributes.uniq
  end

  # Campo de card (#1146) não é condição de regra de conversa/contato.
  def personalizados
    return unless @conta

    @personalizados ||= @conta.custom_attribute_definitions.where.not(attribute_model: :card_attribute)
                              .distinct.pluck(:attribute_key) - padrao
  end

  def propriedades_da_condicao
    {
      'attribute_key' => chave_da_condicao,
      'filter_operator' => um_de((operadores.values.flatten + [MUDOU]).uniq, 'Como comparar o atributo com values.'),
      'values' => { 'type' => %w[array object], 'description' => 'Os valores comparados; com attribute_changed, {from: [...], to: [...]}.' },
      'query_operator' => um_de(QUERY_OPERATORS, 'Liga esta condição à seguinte (AND ou OR); a última vai sem.'),
      'custom_attribute_type' => um_de(['', *TIPOS_DE_ATRIBUTO], 'De quem é o atributo personalizado.')
    }
  end

  def chave_da_condicao
    return um_de(padrao + personalizados, 'O atributo comparado.') if personalizados

    { 'anyOf' => [um_de(padrao, 'Atributo da plataforma.'),
                  valor_da_conta('CustomAttributeDefinition', 'attribute_key', 'Atributo personalizado da conta.')],
      'description' => 'O atributo comparado: da plataforma ou personalizado da conta.' }
  end

  def ramos_das_condicoes
    [*padrao.map { |chave| ramo_da_condicao(chave) }, ramo_da_mudanca, ramo_personalizado]
  end

  def ramo_da_condicao(chave)
    validos = operadores[chave]
    descricao = validos ? "Compara #{chave}.#{NOTAS[chave]}" : "Compara #{chave}; o filtro não tem operador para ela, e a regra não casa."
    entao = { 'properties' => { 'values' => valores_da_condicao(chave) } }
    entao['properties']['filter_operator'] = um_de(validos + [MUDOU], "Operadores de #{chave}.") if validos
    ramo('attribute_key', chave, entao, descricao)
  end

  # attribute_changed compara o antes e o depois: values é um objeto.
  def ramo_da_mudanca
    mudanca = { 'type' => 'object', 'properties' => { 'from' => lista({}), 'to' => lista({}) }, 'additionalProperties' => false }
    entao = { 'properties' => { 'values' => mudanca } }
    ramo('filter_operator', MUDOU, entao, 'Dispara quando o atributo muda (só em conversation_updated).')
  end

  # As duas pontas leem o tipo do atributo com padrões diferentes (a validação procura em
  # conversation_attribute e o filtro em contact_attribute): sem o tipo explícito, um lado não acha.
  def ramo_personalizado
    { 'if' => { 'properties' => { 'attribute_key' => { 'not' => { 'enum' => padrao } } }, 'required' => ['attribute_key'] },
      'then' => { 'required' => ['custom_attribute_type'],
                  'properties' => { 'custom_attribute_type' => um_de(TIPOS_DE_ATRIBUTO, 'De quem é o atributo.') } },
      'description' => 'Atributo personalizado: diga de quem ele é em custom_attribute_type.' }
  end

  def valores_da_condicao(chave)
    item = AutomationRuleSchema::Acoes.valor_do_atributo(*origem(chave))
    { 'anyOf' => [lista(item), { 'type' => 'object' }] }
  end

  # O modelo e a coluna que a condição lê.
  def origem(chave)
    return [::Crm::Card, AutomationRules::CrmConditions::COLUMNS.fetch(chave), nil] if AutomationRules::CrmConditions.key?(chave)

    secao, filtro = SECOES.keys.lazy.map { |nome| [nome, filtros.dig(nome, chave)] }.find { |_nome, item| item }
    [SECOES.fetch(secao, Conversation), chave, filtro&.dig('data_type')]
  end

  # Os operadores de cada condição, na ordem em que o filtro procura (conversa, contato, mensagem).
  def operadores
    @operadores ||= padrao.index_with do |chave|
      AutomationRules::CrmConditions::OPERATORS[chave] ||
        SECOES.keys.lazy.filter_map { |secao| filtros.dig(secao, chave, 'filter_operators') }.first
    end.compact
  end

  def filtros
    self.class.filtros
  end
end

AutomationRuleSchema.prepend_mod_with('AutomationRuleSchema')
