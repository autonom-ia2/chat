# Contrato que o chat2you usa para falar com a máquina de adapters (repo autonomia-adapters).
# Espelha o CLI `autonomia <provider> connection status | capabilities list`. O transporte real
# (HTTP para o serviço do connector) entra na Onda 3; aqui só o contrato + implementação mock.
#
# Retornos são hashes simétricos ao JSON do CLI:
#   connection_status -> { status:, account_label:, session_expires_at:, checked_at: }
#   capabilities      -> { platform:, scanned_at:, products: [...] }
# Erros viram Connector::Error (connector/error.rb) com `kind` estável.
class Autonomia::Insurance::Connector::Client
  def connection_status(provider:, username:, password:)
    raise NotImplementedError
  end

  def capabilities(provider:, username:, password:)
    raise NotImplementedError
  end
end
