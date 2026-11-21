# The Guide's action engine (Autonomia::Guide::Acoes), driven by an app connected over MCP (#3106).
# Same door as the Guide: the user's token through the real endpoint, so Pundit and the account apply as on screen.
# The audit log says it was the app, by name, so the account knows who did it.
class Mcp::Plataforma::Acoes < Autonomia::Guide::Acoes
  AUDITORIA = 'mcp_action'.freeze

  def initialize(app_name:, **)
    @app_name = app_name.to_s
    super(**)
  end

  private

  def trilha = { 'app' => @app_name }
end
