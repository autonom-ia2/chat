# Peças repetidas dos esquemas JSON dos modelos (`AutomationRuleSchema`, `MacroSchema`,
# `Crm::StageAutomationStepSchema`). Cada uma devolve um pedaço de JSON Schema (draft 7) com chaves
# em texto. `x-da-conta` e `description` são anotações: quem valida ignora, quem lê é o Guia.
module JsonSchemaBlocos
  module_function

  # Id de um registro da conta. O validador só confere o tipo; o Guia confere que existe na conta.
  def id_da_conta(modelo, descricao, tipos: 'integer')
    { 'type' => tipos, 'x-da-conta' => { 'modelo' => modelo }, 'description' => descricao }
  end

  # Valor que a conta guarda num campo que não é o id (a etiqueta vai pelo título).
  def valor_da_conta(modelo, campo, descricao)
    { 'type' => 'string', 'x-da-conta' => { 'modelo' => modelo, 'campo' => campo }, 'description' => descricao }
  end

  def texto(descricao)
    { 'type' => 'string', 'minLength' => 1, 'description' => descricao }
  end

  def um_de(valores, descricao)
    { 'enum' => valores, 'description' => descricao }
  end

  def lista(item, minimo: nil, maximo: nil, descricao: nil)
    { 'type' => 'array', 'items' => item, 'minItems' => minimo, 'maxItems' => maximo, 'description' => descricao }.compact
  end

  # Exatamente um item, como o motor lê (`params[0]`).
  def um_item(item, descricao)
    lista(item, minimo: 1, maximo: 1, descricao: descricao)
  end

  # Ação sem parâmetro: o motor ignora o que vier (dado antigo traz nil).
  def nenhum(descricao)
    { 'type' => %w[array null], 'description' => descricao }
  end

  # A lista de ações que o `ActionService` executa: cada item é { action_name, action_params }, e o
  # ramo de cada nome diz o action_params dele.
  def acoes(nomes, ramos, descricao)
    item = { 'type' => 'object', 'required' => ['action_name'], 'additionalProperties' => false,
             'properties' => { 'action_name' => um_de(nomes, 'A ação.'),
                               'action_params' => { 'type' => %w[array null], 'description' => 'Os parâmetros; o ramo da ação diz quais.' } },
             'allOf' => ramos }
    lista(item, descricao: descricao)
  end

  # Um ramo por valor de um campo: quando o objeto tem `campo == valor`, vale `entao`.
  def ramo(campo, valor, entao, descricao, extras = {})
    { 'if' => { 'properties' => { campo => { 'const' => valor } }, 'required' => [campo] },
      'then' => entao, 'description' => descricao }.merge(extras)
  end
end
