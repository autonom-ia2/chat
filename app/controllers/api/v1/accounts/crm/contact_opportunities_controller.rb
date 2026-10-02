# Read-only projection for the shared contact profile; no personal or conversation fields.
class Api::V1::Accounts::Crm::ContactOpportunitiesController < Api::V1::Accounts::Crm::ProfileOpportunitiesController
  def index
    authorize ::Crm::Card, :index?
    return render_unprocessable('crm.contact_opportunities.invalid_parameters') unless valid_parameters?(params[:contact_id])

    contact = Current.account.contacts.find(@record_id)
    authorize contact, :show?
    render_opportunities(policy_scope(::Crm::Card).where(account_id: Current.account.id, contact_id: contact.id))
  end
end
