class Api::V1::Accounts::Crm::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_crm_enabled

  # A duplicate external_id (idempotent upsert race) returns a clean 409 instead
  # of a 500. Stable error envelope for external integrators (n8n).
  rescue_from ActiveRecord::RecordNotUnique do
    render json: {
      error: { code: 'crm.card.external_id_conflict', message: 'A card with this external_id already exists in this account.' }
    }, status: :conflict
  end

  private

  def ensure_crm_enabled
    render json: { error: 'crm.disabled' }, status: :not_found unless ::Crm::Config.enabled?
  end

  def ensure_crm_ai_enabled
    render json: { error: 'crm.ai.disabled' }, status: :not_found unless ::Crm::Ai::Config.enabled?
  end

  def crm_visibility
    @crm_visibility ||= ::Crm::Conversations::Visibility.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    )
  end

  def authorize_crm_conversation!(conversation)
    authorize conversation, :show?
    ::Crm::Conversations::AccessAuthorizer.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    ).authorize!(conversation)
  end

  def render_unprocessable(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def administrator?
    Current.account_user&.administrator?
  end

  def parameter_set(root_key)
    params[root_key].presence || params
  end
end
