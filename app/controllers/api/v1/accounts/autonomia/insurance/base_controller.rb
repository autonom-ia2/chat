class Api::V1::Accounts::Autonomia::Insurance::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :ensure_account_administrator

  private

  # Mesmo gate do menu/rotas do frontend: ENV master + conta marcada. Conta OFF = 404 (recurso invisível).
  def ensure_feature_enabled
    return if ::Autonomia::Insurance::Config.enabled?(Current.account)

    render json: { error: 'autonomia.insurance.disabled' }, status: :not_found
  end

  def ensure_account_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(Current.account).find_or_initialize_by(provider: provider_param)
  end

  def provider_param
    params.fetch(:provider, 'agger')
  end
end
