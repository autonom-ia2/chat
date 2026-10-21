class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :ensure_custom_roles_feature_enabled
  before_action :check_authorization
  before_action :fetch_custom_role, only: [:show, :update, :destroy]

  def index
    @custom_roles = Current.account.custom_roles.for_people
  end

  def show; end

  def create
    grant_guard.write!(nil, permitted_params[:permissions])
    @custom_role = Current.account.custom_roles.create!(permitted_params)
  end

  def update
    grant_guard.write!(@custom_role, permitted_params.fetch(:permissions, @custom_role.permissions))
    @custom_role.update!(permitted_params)
  end

  def destroy
    grant_guard.write!(@custom_role, [])
    @custom_role.destroy!
    head :ok
  end

  def permitted_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.for_people.find(params[:id])
  end

  def grant_guard
    @grant_guard ||= CustomRoles::GrantGuard.new(actor: Current.account_user)
  end

  def ensure_custom_roles_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('custom_roles')
  end
end
