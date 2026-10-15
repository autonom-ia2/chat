# Pausar e retomar o WhatsApp API de uma caixa oficial (#1487), sem desvincular o aparelho.
# Pausar para a sessão no motor SEM logout; retomar religa a mesma sessão, sem QR. Enquanto houver `paused_at`, o
# roteador nunca escolhe o WhatsApp API, nada religa a sessão sozinho (SessionManager#ensure_session!/refresh!) e a
# parada não vira alerta de queda nem sinal de IP ruim (SessionManager#apply_status!).
#
# Lê o motor pelo cliente, sem o SessionManager#fetch_remote (que troca qualquer erro por "sem sessão"): só 404 é
# "sem sessão". Qualquer outra falha do motor recusa o pedido e a conexão fica como estava.
class WhatsappHybrid::Pause
  # Outra troca nesta sessão (pausa, retomada ou troca de proxy) está em andamento.
  class Busy < StandardError; end

  def initialize(connection, client: Waha::Client.new)
    @connection = connection
    @client = client
    @manager = WhatsappHybrid::SessionManager.new(connection, client: client)
  end

  # A pausa é gravada ANTES do stop: o aviso de "parou" que o motor manda em seguida já encontra a conexão pausada.
  # Motor recusou, ou não respondeu e a consulta seguinte não mostra a sessão parada: desfaz a pausa nova e recusa.
  # Pausa já gravada (pedido repetido, ou a sessão voltou a rodar no motor): para de novo, sem desfazer a pausa.
  def pause!
    exclusive do
      remote = remote_session
      fresh = !@connection.paused?
      @connection.update!(paused_at: Time.current, down_alerted_at: nil) if fresh
      stop!(remote, undo: fresh)
      @manager.refresh!
    end
  end

  # Sessão apagada no motor (404) é recriada, com QR. Falha do motor mantém a pausa e recusa o pedido: nada é
  # recriado por cima de uma sessão viva (recriar soltaria a atribuição de proxy dela, #1516).
  # A pausa só sai de vez quando o motor aceitou: recusa (ao recriar ou ao religar) volta a pausa como estava.
  def resume!
    exclusive do
      remote = remote_session
      paused_at = @connection.paused_at
      @connection.update!(paused_at: nil)
      begin
        next @manager.ensure_session! if remote.blank?

        @client.start_session(@connection.session_name) if remote['status'] == 'STOPPED'
        @manager.refresh!
      rescue Waha::Client::Error
        @connection.update!(paused_at: paused_at || Time.current)
        raise
      end
    end
  end

  def qr
    @manager.qr
  end

  private

  # Uma mudança por sessão de cada vez, a mesma trava da troca de proxy (ocupada ou Redis fora: "tente de novo").
  # Relê a conexão depois de pegar a trava (dois administradores ao mesmo tempo). Sem transação de banco: a pausa
  # precisa estar gravada, visível ao webhook, antes do stop.
  def exclusive
    result = WhatsappProxy::SessionLock.with(@connection.session_name) do
      @connection.reload
      yield
    end
    raise Busy if result == :locked

    result
  rescue Redis::BaseError
    raise Busy
  end

  # {} só quando o motor não conhece a sessão.
  def remote_session
    @client.get_session(@connection.session_name) || {}
  rescue Waha::Client::NotFound
    {}
  end

  # undo: a pausa acabou de ser gravada por este pedido (só essa é desfeita quando o motor não para).
  def stop!(remote, undo:)
    return if remote.blank? || remote['status'] == 'STOPPED'

    @client.stop_session(@connection.session_name)
  rescue Waha::Client::Timeout
    # Sem resposta: decide pelo estado real. Parada → a pausa fica; qualquer outra coisa → recusa.
    refuse_stop!(undo) unless confirmed_stopped?
  rescue Waha::Client::Error
    refuse_stop!(undo)
  end

  def confirmed_stopped?
    remote_session['status'] == 'STOPPED'
  rescue Waha::Client::Error
    false
  end

  def refuse_stop!(undo)
    @connection.update!(paused_at: nil) if undo
    raise Waha::Client::Error, 'stop não confirmado'
  end
end
