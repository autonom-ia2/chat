module Enterprise::AutomationRuleSchema
  def parametros
    super.merge(
      'add_sla' => [
        JsonSchemaBlocos.um_item(JsonSchemaBlocos.id_da_conta('SlaPolicy', 'SLA da conta.'), 'O SLA.'),
        'Aplica o SLA à conversa, se a conta tiver SLA ligado e a conversa ainda não tiver um.'
      ]
    )
  end
end
