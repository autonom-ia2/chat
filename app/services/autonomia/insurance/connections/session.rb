# A SESSÃO ÚNICA da conexão com o portal.
#
# O AGGER aceita uma sessão viva por login: abrir outra invalida a anterior. Isso torna a sessão um
# recurso compartilhado da CONEXÃO (conta + provider), não de quem chama — e é por isso que ela mora
# na linha da conexão, e não no chamador.
#
# Sem isto, três coisas quebravam ao mesmo tempo:
#   - uma cotação consulta o resultado de poucos em poucos segundos; cada consulta abria uma sessão
#     nova e invalidava a que a própria cotação estava usando;
#   - duas cotações simultâneas da mesma corretora brigavam pela sessão única;
#   - o healthcheck da tela de Conexões invalidava a sessão de uma cotação em andamento.
#
# CONCORRÊNCIA: o caminho feliz não pega lock (a sessão viva é lida direto). Só quem precisa ABRIR
# entra no `with_lock` e RECHECA lá dentro — duas cotações que começam juntas fazem um login só, e a
# segunda encontra a sessão que a primeira acabou de gravar. Mesmo idioma do resto do namespace.
class Autonomia::Insurance::Connections::Session
  def initialize(connection, connector: ::Autonomia::Insurance::Connector.client)
    @connection = connection
    @connector = connector
  end

  # -> Hash da sessão. Levanta Connector::Error quando não dá para abrir (o chamador traduz em
  # status da conexão, como o Sync já faz).
  def resolve!
    return @connection.session if @connection.session_live?

    open_under_lock!
    session = @connection.session
    raise ::Autonomia::Insurance::Connector::Error.new(:auth_required, 'session unavailable') if session.blank?

    session
  end

  # O portal recusou o que guardamos (sessão encerrada antes do prazo, ou substituída por um login
  # feito fora daqui). Esquece e abre outra. -> Hash da nova sessão.
  def renew!
    @connection.forget_session!
    resolve!
  end

  private

  # O RECHECK dentro do lock é o que faz duas chamadas concorrentes gerarem UM login: a segunda
  # entra, encontra a sessão que a primeira acabou de gravar, e não abre outra.
  #
  # (Correção de 04/09/2026: este comentário afirmava que `return` dentro do `with_lock` dispararia
  # ROLLBACK e descartaria a sessão. Medido no Rails 7.2.3.1 desta aplicação — não dispara, o dado
  # persiste. Era regra de Rails antigo repetida sem conferir. O estilo sem `return` aqui é
  # preferência de leitura, não requisito de correção.)
  def open_under_lock!
    @connection.with_lock do
      open! unless @connection.session_live?
    end
  end

  def open!
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'credentials missing') unless @connection.credentials_present?

    payload = @connector.open_session(provider: @connection.provider, username: @connection.username,
                                      password: @connection.password)
    unless payload.is_a?(Hash) && payload['data'].is_a?(Hash)
      raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'session payload is not a hash')
    end

    @connection.store_session!(payload['data'], expires_at: payload['expires_at'],
                                                account_label: payload['account_label'].to_s.truncate(120).presence)
  end
end
