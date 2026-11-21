Doorkeeper.configure do
  orm :active_record

  # The dashboard is a SPA, so the consent screen is a Vue page that calls JSON endpoints.
  api_only
  base_controller 'ApplicationController'

  resource_owner_authenticator { current_user || authenticate_user! }

  # Every client is public: no secrets, PKCE on every authorization.
  grant_flows %w[authorization_code]
  use_refresh_token
  force_pkce
  pkce_code_challenge_methods %w[S256]

  hash_token_secrets
  allow_token_introspection false
  # A token in a query string ends up in logs, so only the Authorization header is read.
  access_token_methods :from_bearer_authorization

  # account_id: the default account, where the user was on the consent screen.
  # all_accounts (#3106): the connection covers every active account the user administers. Only the new consent screen
  # sets it; a connection made before (or by the previous code during a deploy) stays on its own account. Doorkeeper
  # copies both from the grant to the token, and from each token to the next one on refresh.
  custom_access_token_attributes [:account_id, :all_accounts]

  default_scopes 'conversations:read', 'contacts:read'
  optional_scopes 'conversations:write', 'messages:write', 'contacts:write', 'reports:read'
  enforce_configured_scopes
end
