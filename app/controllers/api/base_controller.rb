class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  include RestrictIntegrationTokenToCrm
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  # Must run AFTER authentication so current_integration_token is resolved (B-T1).
  before_action :restrict_integration_token_to_crm!, if: :integration_token_request?

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  # Admin, or a custom role holding `key` (see AccountUser#permission_granted?).
  def check_permission_granted!(key)
    raise Pundit::NotAuthorizedError unless Current.account_user&.permission_granted?(key)
  end

  # Reads need `<module>_view`, writes `<module>_manage` (#452).
  def check_module_permission!(module_key)
    check_permission_granted!(request.get? || request.head? ? "#{module_key}_view" : "#{module_key}_manage")
  end
end
