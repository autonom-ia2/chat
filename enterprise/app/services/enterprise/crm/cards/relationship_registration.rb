module Enterprise::Crm::Cards::RelationshipRegistration
  private

  def register_company
    input = @input[:company]
    return if input['mode'] == 'none'

    raise Pundit::NotAuthorizedError unless @account.feature_enabled?('companies')

    if input['mode'] == 'existing'
      company = @account.companies.find(input.fetch('id'))
      Pundit.authorize(@user_context, company, :show?)
      return company
    end

    Pundit.authorize(@user_context, Company, :create?)
    reject_company_duplicate!
    company = @account.companies.new(input.fetch('attributes').merge('domain' => normalized_domain))
    validate_values!(company, 'company')
    company.save!
    company
  end

  def attach_company(contact, company)
    # The explicit choice in this form wins over inference from the email domain.
    # Instance-local and transient: native registration/import behavior is unchanged.
    contact.skip_company_auto_association = true
    contact.company = company
  end

  def reject_company_duplicate!
    return unless @input[:company]['mode'] == 'new' && normalized_domain.present?
    raise Pundit::NotAuthorizedError unless @account.feature_enabled?('companies')

    company = @account.companies.find_by(domain: normalized_domain)
    return unless company

    matches = Pundit.policy!(@user_context, company).show? ? [company.slice(:id, :name, :domain)] : []
    raise Crm::Cards::RegistrationInput::Invalid.new('company', { domain: 'taken' }, code: 'company_exists', matches: matches)
  end

  def normalized_domain
    value = @input[:company].dig('attributes', 'domain')
    return nil if value.blank?

    uri = URI.parse(value.include?('://') ? value : "https://#{value}")
    unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?
      raise Crm::Cards::RegistrationInput::Invalid.new('company', { domain: 'invalid' })
    end

    uri.host.downcase.delete_suffix('.')
  rescue URI::InvalidURIError
    raise Crm::Cards::RegistrationInput::Invalid.new('company', { domain: 'invalid' })
  end
end
