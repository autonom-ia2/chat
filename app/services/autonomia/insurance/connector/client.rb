# Contrato que o chat2you usa para falar com a máquina de adapters (repo autonomia-adapters).
# Espelha o CLI `autonomia <provider> connection status | capabilities list`. O transporte real
# (HTTP para o serviço do connector) entra na Onda 3; aqui só o contrato + implementação mock.
#
# Retornos são hashes simétricos ao JSON do CLI:
#   open_session      -> { platform:, data: {...}, expires_at:, account_label:, dropped_previous_session: }
#   connection_status -> { status:, account_label:, session_expires_at:, checked_at: }
#   capabilities      -> { platform:, scanned_at:, products: [...] }
#   quote_start       -> { quote_id:, status: queued|running }
#   quote_result      -> { quote_id:, product:, status: running|partial|completed|failed, offers: [...] }
#   quote_proposal    -> { quote_id:, url: }
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

  # AS DUAS SEM SESSÃO. São conhecimento do adapter sobre o produto, não tocam no portal, e por
  # isso podem correr dentro do turno: é assim que o agente descobre o que perguntar e confere a
  # entrada ANTES de gastar uma cotação, que no AGGER consome consulta paga. Estavam implementadas
  # nas duas pontas (`Http` e `Mock`) e ausentes deste contrato desde que nasceram.
  #   quote_schema   -> { product:, ramo:, campos: [{ campo:, tipo:, origem:, obrigatorio: }] }
  #   quote_validate -> { valido:, problemas: [{ campo:, severidade:, motivo: }] }
  def quote_schema(provider:, product:)
    raise NotImplementedError
  end

  def quote_validate(provider:, product:, input:)
    raise NotImplementedError
  end

  # SUBMETE e volta rápido, com o id da cotação. Uma cotação leva até ~90s: quem espera é o job
  # assíncrono, consultando `quote_result` — nunca esta chamada.
  def quote_start(provider:, session:, product:, input:)
    raise NotImplementedError
  end

  # UMA consulta. `partial` é o estado que permite entregar ao cliente o que já chegou sem esperar
  # a seguradora mais lenta.
  def quote_result(provider:, session:, quote_id:)
    raise NotImplementedError
  end

  # Sem `insurer_code` é o COMPARATIVO, com todas as seguradoras que cotaram — é o que o cliente
  # recebe por padrão, um PDF só. Com `insurer_code`, a proposta daquela seguradora.
  def quote_proposal(provider:, session:, quote_id:, insurer_code: nil)
    raise NotImplementedError
  end
end
