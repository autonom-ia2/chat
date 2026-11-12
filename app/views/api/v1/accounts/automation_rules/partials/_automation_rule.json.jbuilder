json.id automation_rule.id
json.account_id automation_rule.account_id
json.name automation_rule.name
json.description automation_rule.description
json.event_name automation_rule.event_name
json.conditions automation_rule.conditions
# #2450: a URL do webhook sai mascarada para quem não é administrador nem tem integration_manage.
json.actions Autonomia::Automacao::UrlDoWebhook.acoes_da_regra(automation_rule.actions, Current.account_user)
json.created_on automation_rule.created_at.to_i
json.active automation_rule.active?
json.execution_delay automation_rule.execution_delay
json.files automation_rule.file_base_data if automation_rule.files.any?
json.disparos AutomationRules::Disparos.de(automation_rule.id)
