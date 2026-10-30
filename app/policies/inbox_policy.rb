class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      user.assigned_inboxes
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)

    Current.user.assigned_inboxes.include? record
  end

  # Settings pages (#452): members see their inboxes and inbox_view sees every account inbox. Kept apart
  # from show?, which also gates starting conversations and calls in the inbox.
  def settings?
    show? || @account_user.permission_granted?('inbox_view')
  end

  # Members keep creating CSAT templates as before; inbox_view alone only reads them (#452).
  def manage_csat_templates?
    show? || @account_user.permission_granted?('inbox_manage')
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def message_templates?
    true
  end

  def campaigns?
    @account_user.permission_granted?('campaign_view')
  end

  def create?
    inbox_manage?
  end

  def update?
    inbox_manage?
  end

  # The inbox settings save (PATCH /inboxes/:id) also takes integration_manage, only to change how the inbox connects;
  # anything else in it still needs inbox_manage (Api::V1::Accounts::Concerns::InboxCredentialGuard, #2027).
  def update_connection?
    inbox_manage? || @account_user.permission_granted?('integration_manage')
  end

  def destroy?
    inbox_manage?
  end

  def set_agent_bot?
    inbox_manage?
  end

  def avatar?
    inbox_manage?
  end

  def sync_templates?
    inbox_manage?
  end

  # Pasting the Meta management token swaps a credential of a live inbox (#2027): admin or integration_manage.
  def whatsapp_business_management_token?
    @account_user.permission_granted?('integration_manage')
  end

  def health?
    inbox_manage?
  end

  # The API secret and the HMAC token are issued by the platform and leave the account (#452, #2027): admin or
  # token_manage.
  def reset_secret?
    @account_user.permission_granted?('token_manage')
  end

  def rotate_hmac_token?
    @account_user.permission_granted?('token_manage')
  end

  def enable_whatsapp_api_campaigns?
    inbox_manage?
  end

  def disable_whatsapp_api_campaigns?
    inbox_manage?
  end

  def enable_whatsapp_calling?
    inbox_manage?
  end

  def disable_whatsapp_calling?
    inbox_manage?
  end

  def set_inbound_calls?
    inbox_manage?
  end

  def set_call_recording?
    inbox_manage?
  end

  private

  def inbox_manage?
    @account_user.permission_granted?('inbox_manage')
  end
end
