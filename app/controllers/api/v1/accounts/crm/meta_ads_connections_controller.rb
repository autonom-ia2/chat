# Credencial de leitura de anúncios da Meta, uma por conta (#1034). Só administrador.
#
# GET    → { configured, status, last_checked_at, last_error }. Nunca o token nem parte dele.
# PUT    → antes de gravar, testa o token: /me/permissions precisa ter ads_read concedido e
#          /me/adaccounts precisa listar ao menos uma conta de anúncios. Em sucesso grava, devolve o
#          mesmo formato do GET e enfileira a resolução retroativa.
# DELETE → apaga a credencial. Os nomes já resolvidos ficam nos toques e no cache.
#
# Quem não é administrador recebe 403 (não 401: a sessão é válida, só falta a permissão).
class Api::V1::Accounts::Crm::MetaAdsConnectionsController < Api::V1::Accounts::Crm::BaseController
  # Tokens da Meta têm algumas centenas de caracteres; o teto barra corpos absurdos antes da Graph.
  MAX_TOKEN_LENGTH = 2048

  before_action :ensure_administrator

  def show
    render json: payload
  end

  def update
    token = connection_params[:access_token].to_s.strip
    return render_unprocessable('access_token_required') if token.blank?
    return render_unprocessable('access_token_too_long') if token.length > MAX_TOKEN_LENGTH
    return render_unprocessable('encryption_not_configured') unless Chatwoot.encryption_configured?

    error = token_error(Meta::AdsGraphClient.new(access_token: token))
    return render_unprocessable(error) if error

    save_connection!(token)
    Crm::MetaAds::BackfillJob.perform_later(Current.account.id)
    render json: payload
  end

  def destroy
    current_connection&.destroy!
    render json: payload
  end

  private

  def ensure_administrator
    action = { 'show' => :show?, 'update' => :update?, 'destroy' => :destroy? }.fetch(action_name)
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).public_send(action)

    render json: { error: 'forbidden' }, status: :forbidden
  end

  # Ordem: a Meta respondeu? o token vale? tem ads_read? enxerga alguma conta de anúncios?
  # Sem conta atribuída o token "funciona", mas nenhum nome aparece: melhor recusar já aqui.
  def token_error(client)
    permissions = client.permissions
    return graph_failure(permissions) unless permissions.ok
    return 'missing_ads_read' unless Meta::AdsGraphClient.ads_read_granted?(permissions.data)

    accounts = client.ad_accounts_sample
    return graph_failure(accounts) unless accounts.ok

    'no_ad_account' if Array(accounts.data.to_h['data']).empty?
  end

  def graph_failure(result)
    return 'meta_unavailable' if result.transient?
    return 'missing_ads_read' if result.scope_error?

    'invalid_token'
  end

  def save_connection!(token)
    connection = ::Crm::MetaAdsConnection.find_or_initialize_by(account_id: Current.account.id)
    connection.update!(access_token: token, status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end

  def payload
    ::Crm::MetaAdsConnection.public_payload_for(current_connection)
  end

  def connection_params
    parameter_set(:meta_ads_connection).permit(:access_token)
  end
end
