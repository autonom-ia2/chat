class Api::V1::Autonomia::Connect::AgentsController < ApplicationController
  class AccountNotEligible < StandardError; end
  class IntegrationNotFound < StandardError; end

  skip_before_action :authenticate_user!, :set_current_user, raise: false
  before_action :authenticate_connect!

  rescue_from Autonomia::Connect::JwtVerifier::Unauthorized, with: :render_unauthorized_connect
  rescue_from AccountNotEligible, with: :render_forbidden_connect
  rescue_from IntegrationNotFound, with: :render_integration_not_found

  def accounts
    memberships = @connect_user.account_users.includes(:account).where(accounts: { status: Account.statuses[:active] })
    render json: {
      accounts: memberships.map do |membership|
        {
          id: membership.account_id,
          name: membership.account.name,
          role: membership.role,
          eligible: membership.administrator?
        }
      end
    }
  end

  def create
    account, = eligible_account!
    integration = account.mcp_integration_tokens.find_or_create_by!(identity_subject: @identity_subject) do |record|
      record.name = 'Autonom.ia Connect Agents'
      record.created_by = @connect_user
      record.scopes = Mcp::IntegrationToken::DEFAULT_SCOPES
    end

    render_integration(integration, :created)
  end

  def rotate
    _account, integration = eligible_account!
    render_integration(integration, :created, access_token: integration.rotate_access_token!)
  end

  def destroy
    _account, integration = eligible_account!
    integration.revoke!
    head :no_content
  end

  private

  def authenticate_connect!
    payload = Autonomia::Connect::JwtVerifier.new.verify!(request.authorization)
    @identity_subject = payload.fetch('sub')
    @connect_user = Autonomia::UserLink.find_by!(identity_user_id: @identity_subject).user
  rescue ActiveRecord::RecordNotFound
    raise Autonomia::Connect::JwtVerifier::Unauthorized
  end

  def eligible_account!
    membership = @connect_user.account_users.includes(:account).find_by(account_id: params.require(:account_id))
    raise AccountNotEligible unless membership&.administrator? && membership.account.active?

    integration = membership.account.mcp_integration_tokens.find_by(identity_subject: @identity_subject)
    raise IntegrationNotFound if action_name.in?(%w[rotate destroy]) && integration.blank?

    [membership.account, integration]
  end

  def render_integration(integration, status, access_token: nil)
    raw_token = access_token&.token || integration.access_token&.token
    render json: {
      account: { id: integration.account_id, name: integration.account.name },
      scopes: integration.granted_scopes,
      access_token: raw_token
    }, status: status
  end

  def render_unauthorized_connect
    render json: { error: { code: 'UNAUTHORIZED', message: 'Connect authentication is required.' } }, status: :unauthorized
  end

  def render_forbidden_connect
    render json: { error: { code: 'ACCOUNT_NOT_ELIGIBLE', message: 'An account administrator must authorize this connector.' } },
           status: :forbidden
  end

  def render_integration_not_found
    render json: { error: { code: 'INTEGRATION_NOT_FOUND', message: 'Agents integration was not found.' } }, status: :not_found
  end
end
