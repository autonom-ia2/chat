class Api::V1::Accounts::Relationships::ValuesController < Api::V1::Accounts::BaseController
  before_action :validate_context!

  rescue_from Relationships::Configuration::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from Relationships::Configuration::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end

  def update
    record = Current.account.public_send(params[:entity].pluralize).find(params[:id])
    authorize record, :update?
    raise Relationships::Configuration::Invalid, 'field must be an object' unless params[:field].is_a?(ActionController::Parameters)

    attributes = Relationships::ValuePatch.new(record, "#{params[:entity]}_attribute").update!(params[:field].to_unsafe_h)
    render json: { id: record.id, custom_attributes: attributes }
  end

  private

  def validate_context!
    unless Current.account_user && Current.account.feature_enabled?('relationships_attributes') &&
           Current.account.feature_enabled?('custom_attributes')
      return head :forbidden
    end
    raise Relationships::Configuration::Invalid, 'Unknown entity' unless %w[contact company].include?(params[:entity])
    return head :forbidden if params[:entity] == 'company' && !Current.account.feature_enabled?('companies')
  end
end
