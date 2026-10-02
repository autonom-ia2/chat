module Enterprise::Api::V1::Accounts::ContactsController
  private

  def contact_search_scope
    contacts = super
    return contacts unless params[:include_company] == 'true' && Current.account.feature_enabled?('companies')

    @include_company = true
    company_ids = Current.account.companies.search_by_name_or_domain(params[:q]).select(:id)
    contacts.or(Current.account.contacts.where(company_id: company_ids)).includes(:company)
  end

  def permitted_params
    params_with_company_id = super
    return params_with_company_id unless Current.account.feature_enabled?('companies')
    return params_with_company_id unless params.key?(:company_id)

    params_with_company_id.merge(company_id: permitted_company_id)
  end

  def permitted_company_id
    return nil if params[:company_id].blank?

    Current.account.companies.find(params[:company_id]).id
  end
end
