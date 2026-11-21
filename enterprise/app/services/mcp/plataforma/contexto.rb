# Who is asking and what the app did, for one MCP call (#3106). The Guide's context keeps the undo journal: each change
# an app makes stays undoable for 5 days, like the Guide's. The audit entry names the app.
class Mcp::Plataforma::Contexto < Autonomia::Guide::Contexto
  def initialize(app_name:, **)
    @app_name = app_name
    super(**)
  end

  def acoes
    @acoes ||= Mcp::Plataforma::Acoes.new(app_name: @app_name, account: account, user: user, account_user: account_user)
  end
end
