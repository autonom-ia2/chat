class Api::V1::Accounts::Autonomia::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :ensure_account_administrator

  # Onda 6 (P2) — valor de enum inválido (agent_type/actuation/status fora do conjunto) levanta
  # ArgumentError no assign → virava 500. Devolve 422 (erro do cliente). SÓ o erro de enum é tratado
  # aqui; qualquer outro ArgumentError re-sobe (continua 500 — não mascara bug real).
  rescue_from ArgumentError, with: :handle_argument_error
  # #380 — a instrução do Agente de Cotação é mantida pela Autonom.ia. O model levanta em cada escritor
  # da coluna (rollback, refresh, Construtor) e os controllers na porta; a resposta é uma só.
  rescue_from ::Autonomia::Agents::Agent::InstrucaoMantida, with: :render_instrucao_mantida

  private

  def render_instrucao_mantida
    render_unprocessable(I18n.t('autonomia.agents.instrucao_mantida'))
  end

  def handle_argument_error(error)
    raise error unless error.message.include?('is not a valid')

    render json: { error: error.message }, status: :unprocessable_entity
  end

  # Toda a área de Agentes Autonom.ia some (404) quando a flag está desligada — porta única,
  # idêntica ao gate do CRM/EmailCampaigns.
  def ensure_feature_enabled
    head :not_found unless ::Autonomia::Agents::Config.enabled?(Current.account)
  end

  # Só administradores da conta criam/treinam/configuram agentes (construtor é IP e roda jobs de IA).
  # Mesmo padrão usado em endpoints administrativos do core (ex.: oauth_authorization_controller).
  def ensure_account_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  # Escopos sempre presos à conta corrente (isolamento de conta) — nunca consulta global.
  # Agentes de SISTEMA (config['system_key'], ex.: o Guia da Plataforma) ficam FORA da API de
  # agentes: não são listados, lidos, editados nem deletados pelo usuário (instruction = IP nosso).
  def agents_scope
    ::Autonomia::Agents::Agent.where(account: Current.account)
                              .where("config->>'system_key' IS NULL")
  end

  def build_threads_scope
    ::Autonomia::Agents::BuildThread.where(account: Current.account)
  end

  def render_unprocessable(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
