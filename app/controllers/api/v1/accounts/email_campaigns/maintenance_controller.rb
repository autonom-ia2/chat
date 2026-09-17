class Api::V1::Accounts::EmailCampaigns::MaintenanceController < Api::V1::Accounts::EmailCampaigns::BaseController
  wrap_parameters false
  before_action :authorize_maintenance
  rescue_from EmailCampaigns::Maintenance::Request::Invalid, EmailCampaigns::Maintenance::Config::Invalid, with: :invalid_request

  def show
    run = EmailProtectionMaintenanceRun.where(account_id: Current.account.id).find(params[:id])
    authorize run, :show?, policy_class: EmailProtectionMaintenancePolicy
    render json: run.public_progress
  end

  def create
    # Body and query are separate from trusted routing parameters. Never permit an
    # account_id, actor, provider or kind supplied in either payload location.
    input = request.query_parameters.merge(request.request_parameters).except('format')
    run = EmailCampaigns::Maintenance::Start.call(account: Current.account, actor: Current.user, parameters: input)
    render json: run.public_progress, status: :accepted
  end

  def retry
    input = request.query_parameters.merge(request.request_parameters).except('format')
    raise EmailCampaigns::Maintenance::Request::Invalid, 'unsupported_parameter' if input.any?

    run = EmailProtectionMaintenanceRun.where(account_id: Current.account.id).find(params[:id])
    authorize run, :retry?, policy_class: EmailProtectionMaintenancePolicy
    EmailCampaigns::Maintenance::Retry.call(run: run, actor: Current.user)
    render json: run.public_progress, status: :accepted
  end

  private

  def authorize_maintenance
    authorize EmailProtectionMaintenanceRun, :create?, policy_class: EmailProtectionMaintenancePolicy
  end

  def invalid_request(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
