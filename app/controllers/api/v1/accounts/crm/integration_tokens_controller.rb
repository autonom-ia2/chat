# Management API for per-account scoped CRM integration tokens (plan §3.2).
#
# The model (Crm::IntegrationToken) is EE-only and lives under enterprise/, so it
# is only autoloaded in the 'ee' edition this fork runs. index/create/destroy/rotate
# are admin-grade (crm_admin via the EE policy overlay); integration tokens
# themselves can never reach here (RestrictIntegrationTokenToCrm default-denies the
# unmapped integration_tokens controller), so only real session users manage them.
class Api::V1::Accounts::Crm::IntegrationTokensController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_token, only: [:destroy, :rotate]

  # Metadata only — never the secret. The token value is revealed exactly once, at
  # create / rotate time.
  def index
    authorize ::Crm::IntegrationToken
    @integration_tokens = policy_scope(::Crm::IntegrationToken).order(created_at: :desc)
  end

  # Reveal-once: the response body is the only place the plaintext token is exposed.
  def create
    authorize ::Crm::IntegrationToken
    authorize_scopes!(create_params[:scopes])
    @integration_token = Current.account.crm_integration_tokens.new(create_params)
    @integration_token.created_by = Current.user
    @integration_token.save!
    # access_token is created in an after_create callback; load it fresh for the
    # single reveal moment.
    @reveal_token = @integration_token.reload.access_token&.token
    render :show, status: :created
  end

  # Atomic synchronous revocation (B-T2). In ONE transaction: flip status to revoked,
  # synchronously delete the backing AccessToken (NOT destroy_async — the secret must
  # be dead immediately), then destroy the managed AccountUser and its CustomRole.
  # The AccountUser is destroyed first so its custom_role_id can never be observed nil
  # on a surviving row (a nil custom_role hits the CrmPermissions blank-role fallback
  # and would become a CRM superuser — crm_permissions.rb:15).
  def destroy
    authorize @integration_token
    revoke_token!(@integration_token)
    head :ok
  end

  # Rotate = revoke the old credential graph and mint a fresh token carrying the same
  # scopes/name. Reveal-once on the new secret.
  def rotate
    authorize @integration_token
    authorize_scopes!(@integration_token.granted_scopes)
    rotated = nil
    ActiveRecord::Base.transaction do
      rotated = Current.account.crm_integration_tokens.new(
        name: @integration_token.name,
        scopes: @integration_token.granted_scopes,
        created_by: Current.user
      )
      rotated.save!
      revoke_token!(@integration_token)
    end
    @integration_token = rotated
    @reveal_token = rotated.reload.access_token&.token
    render :show, status: :created
  end

  private

  def authorize_scopes!(scopes)
    raise Pundit::NotAuthorizedError unless policy(::Crm::IntegrationToken).grant_scopes?(scopes)
  end

  def revoke_token!(token)
    ActiveRecord::Base.transaction do
      token.update!(status: :revoked)
      AccessToken.where(owner: token).delete_all
      account_user = token.account_user
      custom_role = token.custom_role
      account_user&.destroy!
      custom_role&.destroy!
    end
  end

  def fetch_token
    @integration_token = policy_scope(::Crm::IntegrationToken).find(params[:id])
  end

  def create_params
    params.require(:integration_token).permit(:name, scopes: [])
  end
end
