# Builds the Bearer challenge that tells an MCP client where to start, or extend, the OAuth flow.
module Mcp::BearerChallenge
  def self.build(base_url:, **params)
    params = { resource_metadata: "#{base_url}/.well-known/oauth-protected-resource/mcp" }.merge(params)

    "Bearer #{params.map { |key, value| %(#{key}="#{value}") }.join(', ')}"
  end
end
