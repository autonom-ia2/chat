# POST /api/v1/accounts/:account_id/crm/cards/:card_id/contact
# New contact + existing card link, not another opportunity. Integration tokens
# remain denied by the existing default-deny scope map; no scopes are expanded.
class Api::V1::Accounts::Crm::Cards::ContactsController < Api::V1::Accounts::Crm::BaseController
  include ::Crm::IdempotentRequests

  CONTACT_FIELDS = %w[name email phone_number additional_attributes custom_attributes].freeze
  ADDITIONAL_FIELDS = %w[city country].freeze

  class InvalidContactInput < StandardError; end

  def create
    @card = policy_scope(::Crm::Card).find(params[:card_id])
    authorize @card, :link_contact?
    authorize Contact, :create?
    attributes = contact_attributes
    raise InvalidContactInput, I18n.t('errors.crm.contact_idempotency_required') if request.headers[IDEMPOTENCY_HEADER].blank?

    # Claim, contact, link, activity and saved response commit together. An error
    # must not strand a processing key or leave a person without the intended link.
    ActiveRecord::Base.transaction do
      with_idempotency do
        @card = ::Crm::Cards::ContactCreator.new(card: @card, actor: Current.user, attributes: attributes).perform
        render 'api/v1/accounts/crm/cards/show', status: :created
        ActiveRecord.after_all_transactions_commit do
          ::Crm::Cards::Broadcaster.broadcast(@card, ::Events::Types::CRM_CARD_UPDATED)
        end
      end
    end
  rescue InvalidContactInput => e
    render_unprocessable(e.message)
  rescue ActiveRecord::RecordNotUnique
    # This endpoint creates contacts, so do not report an external_id conflict.
    render_unprocessable(I18n.t('errors.crm.contact_identity_taken'))
  end

  private

  def contact_attributes
    input = params.require(:contact)
    raise InvalidContactInput, I18n.t('errors.crm.invalid_contact_input') unless valid_contact_input?(input)

    attributes = input.permit(:name, :email, :phone_number, additional_attributes: ADDITIONAL_FIELDS, custom_attributes: {}).to_h
    %w[name email phone_number].each do |key|
      attributes[key] = attributes[key].strip if attributes[key].is_a?(String)
    end
    attributes
  end

  def valid_contact_input?(input)
    return false unless input.is_a?(ActionController::Parameters)
    return false unless (input.keys - CONTACT_FIELDS).empty?
    return false unless input[:name].is_a?(String) && input[:name].strip.present?

    optional_strings?(input, %w[email phone_number]) && valid_attribute_objects?(input)
  end

  def optional_strings?(input, keys)
    keys.all? { |key| input[key].nil? || input[key].is_a?(String) }
  end

  def valid_attribute_objects?(input)
    return false unless %w[additional_attributes custom_attributes].all? do |key|
      !input.key?(key) || input[key].is_a?(ActionController::Parameters)
    end

    extra = input[:additional_attributes]
    extra.nil? || ((extra.keys - ADDITIONAL_FIELDS).empty? && optional_strings?(extra, ADDITIONAL_FIELDS))
  end
end
