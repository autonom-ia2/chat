module AccessTokenAuthHelper
  BOT_ACCESSIBLE_ENDPOINTS = {
    'api/v1/accounts/conversations' => %w[show toggle_status toggle_typing_status toggle_priority create update custom_attributes],
    'api/v1/accounts/conversations/messages' => ['create'],
    'api/v1/accounts/conversations/assignments' => ['create'],
    'api/v1/accounts/conversations/labels' => %w[index create]
  }.freeze

  def ensure_access_token
    token = request.headers[:api_access_token] || request.headers[:HTTP_API_ACCESS_TOKEN]
    @access_token = AccessToken.find_by(token: token) if token.present?
  end

  def authenticate_access_token!
    ensure_access_token
    render_unauthorized('Invalid Access Token') && return if @access_token.blank?

    # NOTE: This ensures that current_user is set and available for the rest of the controller actions
    @resource = @access_token.owner

    return if handle_integration_token_auth!

    Current.user = @resource if allowed_current_user_type?(@resource)
  end

  def allowed_current_user_type?(resource)
    return true if resource.is_a?(User)
    return true if resource.is_a?(AgentBot)

    false
  end

  def validate_bot_access_token!
    return if Current.user.is_a?(User)
    return if @resource.is_a?(AgentBot) && agent_bot_accessible?

    render_unauthorized('Access to this endpoint is not authorized for bots')
  end

  def agent_bot_accessible?
    BOT_ACCESSIBLE_ENDPOINTS.fetch(params[:controller], []).include?(params[:action])
  end

  # Scoped integration-token auth. Class-name matching keeps CE builds from
  # autoloading EE-only constants while allowing both CRM and MCP credentials.
  def handle_integration_token_auth!
    return false unless integration_token_resource?(@resource)

    token = @resource

    # Fail-closed: revoked token, or a token whose managed account_user/custom_role
    # was nullified (revocation race) must NEVER fall through to the blank-role
    # CRM superuser path (B-T2).
    if token.revoked? || token.account_user.blank? || token.account_user.custom_role.blank?
      render_unauthorized('Invalid Access Token')
      return true
    end

    token.sync_inbox_memberships! if token.class.name == 'Mcp::IntegrationToken'

    # Resolve to the backing human User + managed AccountUser so Pundit / the EE
    # CrmPermissions policy see a real account_user with the granular custom_role.
    Current.user = token.account_user.user
    Current.account_user = token.account_user
    @current_integration_token = token

    true
  end

  def current_integration_token
    @current_integration_token
  end

  def integration_token_request?
    current_integration_token.present?
  end

  def mcp_integration_token_request?
    current_integration_token&.class&.name == 'Mcp::IntegrationToken'
  end

  private

  def integration_token_resource?(resource)
    resource&.class&.name.in?(%w[Crm::IntegrationToken Mcp::IntegrationToken])
  end
end
