# Serves the Model Context Protocol over Streamable HTTP.
# Every request is self-contained: no session is kept, so any web process can answer it.
# Only administrators may use it (decision of 21/11/2026, #3089). One connection covers every active account
# the user administers (#3106); each tool call names its account, and the account chosen on the consent screen is the default.
class McpController < ApplicationController
  SERVER_NAME = 'chatwoot'.freeze
  INSTRUCTIONS = 'The user may administer several accounts. Call list_accounts to see them, and pass account_id to the ' \
                 'other tools to act on any of them; without it they use the default account.'.freeze

  skip_before_action :set_current_user
  before_action :authenticate_oauth_token!

  def handle
    server = MCP::Server.new(name: SERVER_NAME, version: Chatwoot.config[:version], instructions: INSTRUCTIONS, tools: Mcp::Tools::ALL,
                             server_context: { scopes: doorkeeper_token.scopes.to_a, base_url: public_url,
                                               default_account_id: doorkeeper_token.account_id })
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

    user = User.find_by(id: doorkeeper_token.resource_owner_id)
    # Someone who administers no active account anymore has nothing to connect to: the client starts over.
    return render_oauth_challenge unless Mcp::AccountAccess.new(user).any?

    Current.user = user
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
