# Erro do connector com categoria estável (`kind`): auth_required | unavailable | timeout |
# protocol | validation. Quem chama decide pela categoria, nunca pelo texto (que vem do portal).
class Autonomia::Insurance::Connector::Error < StandardError
  attr_reader :kind, :details

  def initialize(kind, message, details = {})
    super(message)
    @kind = kind
    @details = details
  end
end
