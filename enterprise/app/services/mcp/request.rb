# What one MCP request knows beyond the account: the name of the connected app, for the audit log (#3106).
# Set and cleared by McpController around each request.
module Mcp::Request
  thread_mattr_accessor :app_name
end
