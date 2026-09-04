# Contrato que o chat2you usa para falar com a máquina de adapters (repo autonomia-adapters).
# Espelha o CLI `autonomia <provider> connection status | capabilities list`. O transporte real
# (HTTP para o serviço do connector) entra na Onda 3; aqui só o contrato + implementação mock.
#
# Retornos são hashes simétricos ao JSON do CLI:
#   open_session      -> { platform:, data: {...}, expires_at:, account_label:, dropped_previous_session: }
#   connection_status -> { status:, account_label:, session_expires_at:, checked_at: }
#   capabilities      -> { platform:, scanned_at:, products: [...] }
#
# CREDENCIAL SÓ EM `open_session`. As demais operações viajam com a sessão que ela devolveu: o portal
# aceita uma sessão viva por login, e abrir outra invalida a anterior — inclusive a de uma cotação
# em andamento. `data` é OPACO para nós: guardamos e devolvemos, quem interpreta é o adapter.
# Erros viram Connector::Error (connector/error.rb) com `kind` estável.
class Autonomia::Insurance::Connector::Client
  def open_session(provider:, username:, password:)
    raise NotImplementedError
  end

  def connection_status(provider:, session:)
    raise NotImplementedError
  end

  def capabilities(provider:, session:)
    raise NotImplementedError
  end
end
