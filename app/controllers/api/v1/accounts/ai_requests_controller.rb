class Api::V1::Accounts::AiRequestsController < Api::V1::Accounts::BaseController
  def show
    data = Crm::Ai::InteractiveRequest.read(params[:id])
    return head :not_found unless data && data['account_id'] == Current.account.id && data['account_user_id'] == Current.account_user&.id
    return head :not_found unless data['integration_token_id'] == current_integration_token&.id

    Crm::Ai::InteractiveOperation.new(data).authorize!
    render json: { status: data['status'], result: data['result'] }
  end
end
