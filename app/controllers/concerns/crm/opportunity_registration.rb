module Crm::OpportunityRegistration
  extend ActiveSupport::Concern

  private

  def registration_for_creation
    card = params[:card]
    return unless card.is_a?(ActionController::Parameters) && card.key?(:relationship)

    # Existing integration credentials must not gain contact/company writes implicitly.
    raise Pundit::NotAuthorizedError if integration_token_request?

    input = validated_registration_input(card)
    ::Crm::Cards::RelationshipRegistration.new(account: Current.account, user_context: pundit_user, input: input.to_unsafe_h)
  end

  def validated_registration_input(card)
    input = card[:relationship]
    invalid = !input.is_a?(ActionController::Parameters) || request.headers[::Crm::IdempotentRequests::IDEMPOTENCY_HEADER].blank?
    invalid ||= %w[contact_id conversation_id external_id].any? { |key| card.key?(key) }
    raise ::Crm::Cards::RegistrationInput::Invalid.new('contact', { base: 'invalid' }) if invalid

    input
  end

  def render_registration_error(error)
    status = %w[contact_exists company_exists identity_conflict concurrent_conflict].include?(error.code) ? :conflict : :unprocessable_entity
    render json: { error: { code: "crm.opportunity.#{error.code}", section: error.section, fields: error.fields, matches: error.matches } },
           status: status
  end

  def render_registration_record_error(error)
    record = error.record
    model = record.class.model_name.element
    section = %w[contact company].include?(model) ? model : 'opportunity'
    fields = record.errors.attribute_names.index_with { 'invalid' }
    render_registration_error(::Crm::Cards::RegistrationInput::Invalid.new(section, fields))
  end
end
