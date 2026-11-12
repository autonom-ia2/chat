# Webhook e transcrição por e-mail mandam a conversa para fora da plataforma, como uma integração (#2414, #2448).
# Criar, mudar ou copiar uma regra que tem ou vai ter uma dessas ações pede integration_manage, além de
# automation_manage: ligar, desligar ou tirar o webhook de uma regra também é mexer na integração. Apagar segue só com
# automation_manage. O administrador sempre pode.
module Api::V1::Accounts::Concerns::AutomationExternalActionGuard
  extend ActiveSupport::Concern

  EXTERNAL_ACTIONS = %w[send_webhook_event send_email_transcript].freeze

  private

  # Criar e mudar: as ações que a regra tem hoje e as que vai ter. Sem ações no pedido (ou com `actions: null`), o
  # update mantém as atuais, então valem as atuais (mesmo critério do controller).
  def check_external_actions
    check_integration_for(Array(@automation_rule&.actions) + action_list(params[:actions]))
  end

  # Copiar: as ações da regra de origem (a cópia nasce ligada).
  def check_external_actions_on_clone
    check_integration_for(Current.account.automation_rules.find_by(id: params[:automation_rule_id])&.actions)
  end

  # `external`: as ações que saem da plataforma neste recurso (a macro só tem o webhook nesta regra, #2451).
  def check_integration_for(actions, external = EXTERNAL_ACTIONS)
    names = action_list(actions).filter_map { |action| (action[:action_name] || action['action_name'])&.to_s }
    check_permission_granted!('integration_manage') if names.intersect?(external)
  end

  # Lista de ações, venha em JSON (array) ou em formulário (hash indexado: actions[0][action_name]).
  def action_list(actions)
    return actions.to_unsafe_h.values if actions.respond_to?(:to_unsafe_h)
    return actions.values if actions.is_a?(Hash)

    Array(actions)
  end
end
