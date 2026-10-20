class Api::V1::Accounts::Crm::Cards::BulkController < Api::V1::Accounts::Crm::BaseController
  # Bulk mutation over a set of card ids (move / assign / status / delete).
  # Authorization is two-layered: a coarse `index?` check that the caller may
  # touch cards at all, then, inside the service, the CardPolicy of the action for
  # each card (move?, update?, close?, destroy?; #1874). Refused cards are
  # reported as `forbidden`, never mutated.
  def create
    authorize ::Crm::Card, :index?

    result = ::Crm::Cards::BulkAction.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user,
      ids: params[:ids],
      action: params[:action_name].presence || params[:bulk_action],
      payload: bulk_payload
    ).perform

    render json: { payload: result }
  rescue ::Crm::Cards::BulkAction::InvalidAction => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # `action` is reserved by Rails routing params, so the client sends the bulk
  # verb as `action_name` (preferred) or `bulk_action`.
  def bulk_payload
    parameter_set(:payload).permit(:stage_id, :owner_id, :result).to_h
  end
end
