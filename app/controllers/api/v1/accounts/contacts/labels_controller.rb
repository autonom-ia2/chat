class Api::V1::Accounts::Contacts::LabelsController < Api::V1::Accounts::Contacts::BaseController
  include LabelConcern
  before_action :authorize_label_access!

  private

  def authorize_label_access!
    authorize @contact, request.get? || request.head? ? :show? : :update?
  end

  def model
    @model ||= @contact
  end

  def permitted_params
    params.permit(labels: [])
  end
end
