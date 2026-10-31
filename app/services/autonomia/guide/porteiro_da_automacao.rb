# #2414 F1.3 (D2/D4): montar e ligar automação pelo Guia vale para quem tem `automation_manage`, não só para quem
# administra a conta. Fora as ações de automação, o catálogo segue só para quem administra (Acoes#garantir_permitida!).
# Quem decide no fim é a policy de cada recurso, pelo token da pessoa: a de etapa do CRM também pede
# `crm_manage_pipelines`.
class Autonomia::Guide::PorteiroDaAutomacao
  ACOES = [
    'POST automation_rules', 'PATCH automation_rules/:id', 'PUT automation_rules/:id', 'DELETE automation_rules/:id',
    'POST automation_rules/:automation_rule_id/clone', 'POST automation_rules/:id/ensaio',
    'POST crm/stages/:stage_id/stage_automations', 'PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id',
    'DELETE crm/stage_automations/:id', 'POST crm/stage_automations/:stage_automation_id/steps',
    'PATCH crm/stage_automations/:stage_automation_id/steps/:id', 'PUT crm/stage_automations/:stage_automation_id/steps/:id',
    'DELETE crm/stage_automations/:stage_automation_id/steps/:id'
  ].freeze

  def self.de_automacao?(acao) = ACOES.include?(acao.to_s)

  # nil quando pode; senão a chave i18n da recusa.
  def self.recusa(acao, account_user)
    return 'admin_only' unless de_automacao?(acao)

    'automation_manage_only' unless account_user.present? && account_user.permission_granted?('automation_manage')
  end
end
