class Api::V1::Accounts::Contacts::MediaController < Api::V1::Accounts::Contacts::BaseController
  include Relationships::MediaActions

  before_action :ensure_media_enabled!
  before_action :authorize_contact_read!
  before_action :private_response!
  rescue_from Relationships::Configuration::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def relationship_record
    @contact
  end

  def authorize_contact_read!
    authorize @contact, :show?
  end

  def ensure_media_enabled!
    head :forbidden unless Current.account_user && Current.account.feature_enabled?('companies') &&
                           Current.account.feature_enabled?('relationships_company_media')
  end
end
