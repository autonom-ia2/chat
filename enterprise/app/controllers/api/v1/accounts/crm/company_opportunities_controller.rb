class Api::V1::Accounts::Crm::CompanyOpportunitiesController < Api::V1::Accounts::Crm::ProfileOpportunitiesController
  include ::Crm::Cards::CompanyFilters

  before_action :ensure_companies_enabled!

  def index
    authorize ::Crm::Card, :index?
    return render_unprocessable('crm.company_opportunities.invalid_parameters') unless valid_parameters?(params[:company_id])

    company = Current.account.companies.find(@record_id)
    authorize company, :show?
    # Same company rule as the board, list, filter and export: the opportunity's
    # prospecting company (same account) wins, otherwise the contact's canonical
    # company. Never company_name text or matching email domains.
    cards = policy_scope(::Crm::Card).where(account_id: Current.account.id)
                                     .where(resolved_company_match_sql, company.id, company.id)
    render_opportunities(cards, include_contact: true)
  end

  private

  def ensure_companies_enabled!
    return if Current.account.feature_enabled?('companies')

    render json: { error: 'Companies are not enabled for this account' }, status: :forbidden
  end
end
