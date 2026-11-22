module Enterprise::Api::V1::Accounts::ContactsController
  private

  # Nova mensagem para o contato de uma conversa que a pessoa vê vale sem contact_view (#1849): a decisão depende do
  # contato, então esta ação autoriza o registro em vez da classe.
  def check_authorization(model = nil)
    return super unless action_name == 'contactable_inboxes'

    authorize(Current.account.contacts.find(params[:id]), :contactable_inboxes?)
  end

  def contact_search_scope
    contacts = super
    return contacts unless params[:include_company] == 'true' && Current.account.feature_enabled?('companies')

    @include_company = true
    company_ids = Current.account.companies.search_by_name_or_domain(params[:q]).select(:id)
    contacts.or(Current.account.contacts.where(company_id: company_ids)).includes(:company)
  end
end
