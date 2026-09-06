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

  # Roda o bloco com a sessão da conexão e, se o PORTAL recusar essa sessão, esquece, abre outra e
  # tenta UMA vez. -> o que o bloco devolver.
  #
  # `session_live?` só sabe do prazo que nós gravamos. Ele não sabe que alguém entrou no portal pelo
  # navegador e derrubou a nossa — o AGGER aceita uma sessão por login. Nesse caso a linha fica com
  # uma sessão que parece viva, e toda chamada morre em 403 até o prazo vencer.
  #
  # Foi o que aconteceu em 05/09/2026, horas depois de a sessão única entrar no ar: o corretor abriu
  # o portal, a nossa sessão caiu, e a tela passou a dizer "credencial recusada" com a credencial
  # perfeitamente válida. `renew!` já existia para exatamente isto e não era chamado por ninguém.
  #
  # UMA tentativa, não um laço: se o login novo também for recusado, o problema é a credencial, e
  # insistir só multiplica login no portal.
  def with_fresh_session
    yield resolve!
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :auth_required && @connection.session.present?

    yield renew!
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
    registrar_conta_em_uso(payload)
  end

  # CRITERIO 1.5 — a mesma conta AGGER usada em dois lugares ao mesmo tempo.
  #
  # Decisao do Rodrigo em 06/09/2026: AVISAR, nao bloquear. Bloquear tiraria a capacidade de testar
  # com a conta real, e o dano hoje e confusao — dois logins nossos convivem sem se derrubar, isso
  # foi medido. O que confunde e o corretor abrir o portal e ver cotacao de teste misturada com a
  # do cliente, sem saber qual e qual.
  #
  # O aviso nao foi inventado: o portal o da, no mesmo 201 do login bem-sucedido. Era descartado
  # porque o login tinha dado certo, e sucesso ninguem olha duas vezes.
  #
  # `nil` quando o adapter nao informa — sessao aberta por versao anterior. Ausente e "nao sei",
  # que e diferente de "nao havia ninguem".
  def registrar_conta_em_uso(payload)
    return unless payload.key?('already_active')

    @connection.merge_metadata!(
      'account_already_active' => if payload['already_active']
                                    {
                                      'observed_at' => Time.current.iso8601,
                                      'session_started_at' => payload['session_started_at']
                                    }
                                  end
    )
  end
end
