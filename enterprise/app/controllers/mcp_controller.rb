# Serves the Model Context Protocol over Streamable HTTP.
# Every request is self-contained: no session is kept, so any web process can answer it.
# Only administrators of the account the token is bound to may use it (decision of 21/11/2026, #3089).
class McpController < ApplicationController
  SERVER_NAME = 'chatwoot'.freeze

  skip_before_action :set_current_user
  before_action :authenticate_oauth_token!

  def handle
    server = MCP::Server.new(name: SERVER_NAME, version: Chatwoot.config[:version], tools: Mcp::Tools::ALL,
                             server_context: { scopes: doorkeeper_token.scopes.to_a, base_url: public_url })
    # Rails already checks the Host header, and the bearer token rules out cross-site browser requests.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true,
                                                                             dns_rebinding_protection: false)
    server.transport = transport

    status, headers, body = transport.handle_request(request)
    response.headers.merge!(headers)
    self.status = status
    self.response_body = body
  end

  private

  def authenticate_oauth_token!
    return render_oauth_challenge unless doorkeeper_token&.accessible?

    account_user = AccountUser.find_by(user_id: doorkeeper_token.resource_owner_id, account_id: doorkeeper_token.account_id)
    return render_oauth_challenge unless account_user&.administrator? && account_user.account&.active?

    Current.account_user = account_user
    Current.account = account_user.account
    Current.user = account_user.user
  end

  # The header tells the client where to find the authorization server, which starts the OAuth flow.
  def render_oauth_challenge
    response.headers['WWW-Authenticate'] = Mcp::BearerChallenge.build(base_url: public_url)
    head :unauthorized
  end

  def public_url
    Oauth::PublicUrl.for(request)
  end
end
