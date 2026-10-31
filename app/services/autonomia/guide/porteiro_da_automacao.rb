# #2414 F1.3 (D2/D4): montar e ligar automação pelo Guia vale para quem tem a chave de automação, não só para quem
# administra a conta. Fora estas ações, o catálogo segue só para quem administra (Acoes#garantir_permitida!).
# A chave de cada ação é a mesma da policy do recurso (AutomationRulePolicy, Autonomia::DecisorPolicy), e quem decide no
# fim é a policy, pelo token da pessoa: a de etapa do CRM também pede `crm_manage_pipelines`.
class Autonomia::Guide::PorteiroDaAutomacao
  MONTAR = [
    'POST automation_rules', 'PATCH automation_rules/:id', 'PUT automation_rules/:id', 'DELETE automation_rules/:id',
    'POST automation_rules/:automation_rule_id/clone',
    'POST crm/stages/:stage_id/stage_automations', 'PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id',
    'DELETE crm/stage_automations/:id', 'POST crm/stage_automations/:stage_automation_id/steps',
    'PATCH crm/stage_automations/:stage_automation_id/steps/:id', 'PUT crm/stage_automations/:stage_automation_id/steps/:id',
    'DELETE crm/stage_automations/:stage_automation_id/steps/:id',
    'POST autonomia/decisores', 'PATCH autonomia/decisores/:id', 'PUT autonomia/decisores/:id', 'DELETE autonomia/decisores/:id',
    'POST autonomia/decisores/:id/teste', 'POST autonomia/decisores/:id/exemplos', 'POST autonomia/decisoes/:id/resolver'
  ].index_with('automation_manage')

  # O ensaio só lê: mostra o que a regra faria (#859).
  CHAVE_POR_ACAO = MONTAR.merge('POST automation_rules/:id/ensaio' => 'automation_view').freeze

  # nil quando pode; senão a chave i18n da recusa.
  def self.recusa(acao, account_user)
    chave = CHAVE_POR_ACAO[acao.to_s]
    return 'admin_only' if chave.nil?

    'automation_manage_only' unless account_user.present? && account_user.permission_granted?(chave)
  end
end
