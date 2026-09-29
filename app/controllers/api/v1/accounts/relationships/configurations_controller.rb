class Api::V1::Accounts::Relationships::ConfigurationsController < Api::V1::Accounts::BaseController
  before_action :ensure_enabled!
  rescue_from Relationships::Configuration::Invalid, with: :invalid
  rescue_from Relationships::Configuration::Conflict, with: :conflict

  def show
    authorize CustomAttributeDefinition, :index?
    render json: { configuration: service.read, definitions: definitions.map { |definition| service.serialize_definition(definition) },
                   can_manage: Current.account_user.permission_granted?('attribute_manage') }
  end

  def update
    authorize CustomAttributeDefinition, :update?
    raise Relationships::Configuration::Invalid, 'configuration must be an object' unless params[:configuration].is_a?(ActionController::Parameters)

    render json: service.update!(params[:configuration].to_unsafe_h)
  end

  private

  def definitions
    scope = Current.account.custom_attribute_definitions.order(:id)
    Current.account.feature_enabled?('companies') ? scope : scope.where.not(attribute_model: :company_attribute)
  end

  def service
    Relationships::Configuration.new(Current.account)
  end

  def ensure_enabled!
    unless Current.account_user && Current.account.feature_enabled?('relationships_attributes') &&
           Current.account.feature_enabled?('custom_attributes')
      head :forbidden
    end
  end

  def invalid(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def conflict(error)
    render json: { error: error.message }, status: :conflict
  end
end
