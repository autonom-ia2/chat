# Conexão da conta com os anúncios da Meta (#1034, #1047). Só administrador.
#
# GET    → estado da conexão (nunca o token), dados do portfólio parceiro da plataforma e o estado de
#          "avisar a Meta quando vender".
# PUT    → modo `token`: testa o token colado (ads_read concedido e ao menos uma conta de anúncios) e grava.
# DELETE → apaga a conexão. Os nomes já resolvidos ficam nos toques e no cache.
#
# Conexão guiada (#1047):
# GET   ad_accounts?mode=  → contas de anúncios que esta conta pode usar, a recomendada primeiro
# GET   pixels?mode=&ad_account_id= → Pixels da conta de anúncios
# POST  selection    → lê a conta e o Pixel de verdade e só então grava (CA-1.2)
# PATCH destinations → para onde os anúncios levam: WhatsApp, site ou os dois
# POST  sales_signal → liga ou desliga o envio das vendas à Meta nos funis ativos
#
# Quem não é administrador recebe 403 (não 401: a sessão é válida, só falta a permissão).
class Api::V1::Accounts::Crm::MetaAdsConnectionsController < Api::V1::Accounts::Crm::BaseController
  # Tokens da Meta têm algumas centenas de caracteres; o teto barra corpos absurdos antes da Graph.
  MAX_TOKEN_LENGTH = 2048
  READ_ACTIONS = %w[show ad_accounts pixels].freeze

  before_action :ensure_administrator
  before_action :ensure_mode, only: [:ad_accounts, :pixels, :selection]

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

  def ad_accounts
    render json: { ad_accounts: setup.ad_accounts(params[:mode]) }
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  end

  def pixels
    render json: { pixels: setup.pixels(params[:mode], params[:ad_account_id].to_s) }
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  end

  def selection
    setup.select!(mode: params[:mode], ad_account_id: params[:ad_account_id].to_s, pixel_id: params[:pixel_id].presence&.to_s)
    render json: payload
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render_unprocessable('ad_account_in_use')
  end

  def destinations
    connection = current_connection
    return render_unprocessable('not_connected') if connection.blank?

    bool = ActiveModel::Type::Boolean.new
    values = ::Crm::MetaAdsConnection::DESTINATIONS.index_with { |key| bool.cast(params.dig(:destinations, key)) == true }
    connection.update!(destinations: values)
    render json: payload
  end

  def sales_signal
    connection = current_connection
    return render_unprocessable('not_connected') if connection.blank?

    ::Crm::MetaAds::SalesSignal.new(Current.account, connection).update!(ActiveModel::Type::Boolean.new.cast(params[:enabled]) == true)
    render json: payload
  end

  private

  def ensure_administrator
    action = policy_action
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).public_send(action)

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def policy_action
    return :show? if READ_ACTIONS.include?(action_name)

    action_name == 'destroy' ? :destroy? : :update?
  end

  def ensure_mode
    render_unprocessable('invalid_mode') unless ::Crm::MetaAdsConnection::MODES.include?(params[:mode])
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

  # Colar um token novo volta a conexão ao modo `token`; a conta de anúncios escolhida antes só continua
  # se o novo token também a enxergar, o que a escolha seguinte confere.
  def save_connection!(token)
    connection = ::Crm::MetaAdsConnection.find_or_initialize_by(account_id: Current.account.id)
    connection.update!(access_token: token, mode: 'token', status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  def setup
    @setup ||= ::Crm::MetaAds::Setup.new(Current.account)
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end

  def payload
    connection = current_connection
    ::Crm::MetaAdsConnection.public_payload_for(connection).merge(
      partner: ::Crm::MetaAds::Platform.public_payload,
      whatsapp_portfolio: setup.portfolio_ids.any?,
      sales_signal: ::Crm::MetaAds::SalesSignal.new(Current.account, connection).payload
    )
  end

  def connection_params
    parameter_set(:meta_ads_connection).permit(:access_token)
  end
end
