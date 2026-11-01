# Webhook e transcrição por e-mail mandam a conversa para fora da plataforma, como uma integração (#2414). Criar,
# mudar ou copiar uma regra que tem uma dessas ações pede integration_manage, além de automation_manage. Vale pelo que
# a regra vai ter depois de salva: na edição sem ações novas, as que ela já tem. Apagar segue só com automation_manage.
# O administrador sempre pode.
module Api::V1::Accounts::Concerns::AutomationExternalActionGuard
  extend ActiveSupport::Concern

  EXTERNAL_ACTIONS = %w[send_webhook_event send_email_transcript].freeze

  private

  # Criar e mudar: as ações que vêm no pedido ou, na edição sem ações novas, as que a regra já tem.
  def check_external_actions
    actions = params.key?(:actions) ? params[:actions] : @automation_rule&.actions
    check_integration_for(actions)
  end

  # Copiar: as ações da regra de origem (a cópia nasce ligada).
  def check_external_actions_on_clone
    check_integration_for(Current.account.automation_rules.find_by(id: params[:automation_rule_id])&.actions)
  end

  def check_integration_for(actions)
    names = Array(actions).filter_map { |action| (action[:action_name] || action['action_name'])&.to_s }
    check_permission_granted!('integration_manage') if names.intersect?(EXTERNAL_ACTIONS)
  end
end
