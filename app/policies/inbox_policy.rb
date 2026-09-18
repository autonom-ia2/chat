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

  # Credentials stay admin-only even for inbox_manage (#452): the token and the secret leave the account.
  def whatsapp_business_management_token?
    @account_user.administrator?
  end

  def health?
    inbox_manage?
  end

  def reset_secret?
    @account_user.administrator?
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

  private

  def inbox_manage?
    @account_user.permission_granted?('inbox_manage')
  end
end
