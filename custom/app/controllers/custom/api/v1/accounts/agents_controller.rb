# frozen_string_literal: true

module Custom::Api::V1::Accounts::AgentsController
  def create
    return super unless autonomia_product_invitations_enabled?

    invitation = Autonomia::ProductInvitations::AgentInviter.new(
      account: Current.account,
      inviter: current_user,
      agent_params: autonomia_agent_params.to_h.merge('custom_role_id' => invited_custom_role_id)
    ).perform

    render json: {
      pending_invitation: true,
      email: invitation.email,
      name: invitation.name,
      role: invitation.role,
      invitation_url: invitation.invitation_url,
      expires_in_hours: invitation.expires_in_hours,
      email_delivery_failed: invitation.email_delivery_failed,
      manual_share_required: invitation.manual_share_required,
      email_delivery_error: invitation.email_delivery_error
    }, status: :created
  rescue Autonomia::ProductInvitations::AgentInviter::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # The invitation also adds the person to inboxes and may create a WhatsApp inbox: that part needs inbox_manage, not
  # only people_manage (#1931).
  def guard_new_agent!
    super
    return unless autonomia_product_invitations_enabled?

    inbox_part = autonomia_agent_params[:inbox_ids].present? ||
                 ActiveModel::Type::Boolean.new.cast(autonomia_agent_params[:create_whatsapp_api_inbox])
    raise Pundit::NotAuthorizedError if inbox_part && !Current.account_user.permission_granted?('inbox_manage')
    raise Pundit::NotAuthorizedError if replaces_someone_elses_invitation?
  end

  # A pending invitation is keyed by e-mail: a non-administrator does not overwrite one someone else made.
  def replaces_someone_elses_invitation?
    return false if Current.account_user.administrator?

    pending = Current.account.custom_attributes&.dig('autonomia_pending_agent_invitations',
                                                     autonomia_agent_params[:email].to_s.downcase)
    pending.present? && pending['invited_by_user_id'].to_i != current_user.id
  end

  def autonomia_product_invitations_enabled?
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch('AUTONOMIA_PRODUCT_INVITATIONS_ENABLED', ENV.fetch('AUTONOMIA_SSO_ENABLED', false))
    )
  end

  # Like the direct create, a custom role only travels when the account has the feature (#1931).
  def invited_custom_role_id
    custom_role_id_param if Current.account.feature_enabled?('custom_roles')
  end

  # The Enterprise controller reads and checks it (a single id only, #1931); this is the fallback without Enterprise.
  def custom_role_id_param
    defined?(super) ? super : (params.dig(:agent, :custom_role_id).presence || params[:custom_role_id])
  end

  def autonomia_agent_params
    params.require(:agent).permit(
      :email,
      :name,
      :role,
      :availability,
      :auto_offline,
      :create_whatsapp_api_inbox,
      :whatsapp_api_phone,
      inbox_ids: []
    )
  end
end
