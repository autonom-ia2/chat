class Api::V1::Accounts::Crm::CompanyOpportunitiesController < Api::V1::Accounts::Crm::ProfileOpportunitiesController
  before_action :ensure_companies_enabled!

  def index
    authorize ::Crm::Card, :index?
    return render_unprocessable('crm.company_opportunities.invalid_parameters') unless valid_parameters?(params[:company_id])

    company = Current.account.companies.find(@record_id)
    authorize company, :show?
    # The current canonical association is authoritative, never company_name,
    # matching email domains or a historical snapshot in the opportunity.
    contacts = Current.account.contacts.where(company_id: company.id).select(:id)
    cards = policy_scope(::Crm::Card).where(account_id: Current.account.id, contact_id: contacts)
    render_opportunities(cards, include_contact: true)
  end

  private

  def ensure_companies_enabled!
    return if Current.account.feature_enabled?('companies')

    render json: { error: 'Companies are not enabled for this account' }, status: :forbidden
  end
end
