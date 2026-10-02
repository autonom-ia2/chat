# One native contact registration inside cards#create's encompassing transaction.
# Company behavior is provided by the Enterprise overlay, never a parallel model.
class Crm::Cards::RelationshipRegistration
  Invalid = Crm::Cards::RegistrationInput::Invalid

  def initialize(account:, user_context:, input:)
    @account = account
    @user_context = user_context
    @input = Crm::Cards::RegistrationInput.new(input).perform
  end

  def perform
    Pundit.authorize(@user_context, Contact, :create?)
    # Serialize registrations in this flow, including different idempotency keys.
    # Existing phone indexes are not globally unique; other writers remain a release review item.
    # Idempotency claims already reference the account (FOR KEY SHARE). Do not
    # upgrade those foreign-key locks to FOR UPDATE in two competing requests.
    @account.with_lock('FOR NO KEY UPDATE') do
      reject_contact_duplicate!
      company = register_company
      contact = @account.contacts.new(@input[:contact].merge(contact_type: :lead))
      attach_company(contact, company)
      validate_values!(contact, 'contact')
      contact.save!
      yield contact
    end
  end

  def conflict
    reject_contact_duplicate!
    reject_company_duplicate!
    Invalid.new('contact', {}, code: 'concurrent_conflict')
  rescue Invalid => e
    e
  end

  private

  def contact_candidates
    identity = @input[:contact]
    scope = @account.contacts.none
    scope = scope.or(@account.contacts.where('LOWER(email) = ?', identity['email'])) if identity['email'].present?
    scope = scope.or(@account.contacts.where(phone_number: identity['phone_number'])) if identity['phone_number'].present?
    scope.order(:id).limit(3).to_a
  end

  def reject_contact_duplicate!
    candidates = contact_candidates
    return if candidates.empty?

    visible = candidates.select { |contact| Pundit.policy!(@user_context, contact).show? }
    matches = visible.map { |contact| contact.slice(:id, :name, :email, :phone_number) }
    code = candidates.length > 1 ? 'identity_conflict' : 'contact_exists'
    raise Invalid.new('contact', {}, code: code, matches: matches)
  end

  def register_company
    return if %w[none auto].include?(@input[:company]['mode'])

    raise Pundit::NotAuthorizedError
  end

  def attach_company(_contact, _company); end

  def reject_company_duplicate!; end

  def validate_values!(record, entity)
    definitions = @account.custom_attribute_definitions.where(attribute_model: "#{entity}_attribute").index_by(&:attribute_key)
    (record.custom_attributes || {}).each do |key, value|
      definition = definitions[key]
      next if native_contact_detail?(entity, key, value, definition)

      validate_attribute_value!(definition, value, entity, key)
    end
  end

  def native_contact_detail?(entity, key, value, definition)
    entity == 'contact' && %w[address job_title].include?(key) && value.is_a?(String) && definition.nil?
  end

  def validate_attribute_value!(definition, value, entity, key)
    raise Invalid.new(entity, { "custom_attributes.#{key}" => 'unavailable' }) unless definition && @account.feature_enabled?('custom_attributes')

    Relationships::ValueValidator.new(definition).validate!(value)
  rescue Relationships::Configuration::Invalid
    raise Invalid.new(entity, { "custom_attributes.#{key}" => 'invalid' })
  end
end

Crm::Cards::RelationshipRegistration.prepend_mod_with('Crm::Cards::RelationshipRegistration')
