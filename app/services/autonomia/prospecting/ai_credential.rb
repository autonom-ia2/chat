# A IA DA PROSPECÇÃO RODA SÓ NA CREDENCIAL DO KANBAN CRM DA CONTA (chat#683).
#
# Diferente do `Crm::Ai::CredentialResolver`, não cai na `CAPTAIN_OPEN_AI_API_KEY` da instalação: a prospecção é
# produto vendido à parte, e o consumo de IA dela é da conta. Sem hook `crm_kanban_ai` ligado com `api_key`, não há
# credencial, e quem chama segue sem IA.
class Autonomia::Prospecting::AiCredential
  APP_ID = 'crm_kanban_ai'.freeze
  DEFAULT_API_BASE = 'https://api.openai.com'.freeze

  def initialize(account:)
    @account = account
  end

  def resolve
    hook = @account.hooks.enabled.account_hooks.find_by(app_id: APP_ID)
    return if hook.blank?

    settings = hook.settings.to_h
    return if settings['enabled'] == false

    api_key = settings['api_key'].presence
    return if api_key.blank?

    { api_key: api_key, api_base: settings['api_base'].presence || DEFAULT_API_BASE, source: :hook }
  end

  def configured?
    resolve.present?
  end
end
