# A regra interna da coluna `actions` de Macro, como esquema JSON (#932). A macro executa as ações
# do `ActionService` (`Macros::ExecutionService`), então cada ramo é o mesmo da regra de automação,
# com uma diferença: em `assign_agent`, `self` é quem executa a macro.
#
# Nenhum ramo é `x-sem-volta`: criar a macro não manda nada. Quem manda é executá-la, e executar já
# pede confirmação no Guia (`Autonomia::Guide::Acoes::SEM_DESFAZER`).
module MacroSchema
  extend JsonSchemaBlocos

  module_function

  def actions(_macro = nil)
    ramos = parametros.map do |nome, (parametro, descricao)|
      ramo('action_name', nome, { 'properties' => { 'action_params' => parametro } }, descricao)
    end
    acoes(Macro::ACTIONS_ATTRS, ramos, 'O que a macro faz, na ordem, quando alguém a executa numa conversa.')
  end

  def parametros
    AutomationRuleSchema::Acoes.parametros.slice(*Macro::ACTIONS_ATTRS).merge('assign_agent' => assign_agent)
  end

  def assign_agent
    agente = { 'anyOf' => [id_da_conta('User', 'Agente da conta.'), um_de(%w[nil self], 'nil tira o agente; self é quem executa a macro.')] }
    [lista(agente, minimo: 1, descricao: 'O agente; o motor usa o primeiro.'),
     'Atribui a conversa ao agente. Só funciona se ele for da caixa ou administrador; id vai como número.']
  end
end
