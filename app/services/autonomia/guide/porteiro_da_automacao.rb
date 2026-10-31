# #2414 F1.3 (D2/D4): montar e ligar automação pelo Guia vale para quem tem a chave de automação, não só para quem
# administra a conta. Fora estas ações, o catálogo segue só para quem administra (Acoes#garantir_permitida!).
# As chaves de cada ação são as mesmas da policy do recurso (AutomationRulePolicy, Autonomia::DecisorPolicy e, na etapa
# do CRM, StageAutomationPolicy), para o Guia não propor o que a plataforma vai recusar. Quem decide no fim é a policy,
# pelo token da pessoa.
class Autonomia::Guide::PorteiroDaAutomacao
  REGRAS = [
    'POST automation_rules', 'PATCH automation_rules/:id', 'PUT automation_rules/:id', 'DELETE automation_rules/:id',
    'POST automation_rules/:automation_rule_id/clone',
    'POST autonomia/decisores', 'PATCH autonomia/decisores/:id', 'PUT autonomia/decisores/:id', 'DELETE autonomia/decisores/:id',
    'POST autonomia/decisores/:id/teste', 'POST autonomia/decisores/:id/exemplos', 'POST autonomia/decisoes/:id/resolver'
  ].freeze

  ETAPA = [
    'POST crm/stages/:stage_id/stage_automations', 'PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id',
    'DELETE crm/stage_automations/:id', 'POST crm/stage_automations/:stage_automation_id/steps',
    'PATCH crm/stage_automations/:stage_automation_id/steps/:id', 'PUT crm/stage_automations/:stage_automation_id/steps/:id',
    'DELETE crm/stage_automations/:stage_automation_id/steps/:id'
  ].freeze

  # Recusa (chave i18n) => o que a pessoa precisa ter: cada grupo é uma alternativa de chaves, e todos os grupos valem.
  # Na etapa do CRM, `crm_admin` vale por `crm_manage_pipelines`, como no CrmPermissions.
  EXIGENCIAS = {
    'automation_manage_only' => [%w[automation_manage]],
    'stage_automation_manage_only' => [%w[automation_manage], %w[crm_manage_pipelines crm_admin]],
    # O ensaio só lê: mostra o que a regra faria (#859).
    'automation_view_only' => [%w[automation_view]]
  }.freeze

  RECUSA_POR_ACAO = REGRAS.index_with('automation_manage_only')
                          .merge(ETAPA.index_with('stage_automation_manage_only'))
                          .merge('POST automation_rules/:id/ensaio' => 'automation_view_only').freeze

  # nil quando pode; senão a chave i18n da recusa.
  def self.recusa(acao, account_user)
    recusa = RECUSA_POR_ACAO[acao.to_s]
    return 'admin_only' if recusa.nil?
    return recusa if account_user.blank?

    recusa unless EXIGENCIAS.fetch(recusa).all? { |alternativas| alternativas.any? { |chave| account_user.permission_granted?(chave) } }
  end
end
