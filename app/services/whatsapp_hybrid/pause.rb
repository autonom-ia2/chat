# Pausar e retomar o WhatsApp API de uma caixa oficial (#1487), sem desvincular o aparelho.
# Pausar para a sessão no motor SEM logout; retomar religa a mesma sessão, sem QR. Enquanto houver `paused_at`, o
# roteador nunca escolhe o WhatsApp API, nada religa a sessão sozinho (SessionManager#ensure_session!/refresh!) e a
# parada não vira alerta de queda (Connection#routable_when_connected?).
class WhatsappHybrid::Pause
  def initialize(connection, client: Waha::Client.new)
    @connection = connection
    @client = client
    @manager = WhatsappHybrid::SessionManager.new(connection, client: client)
  end

  # A pausa é gravada antes do pedido, já fora do ar: o aviso de "parou" que o motor manda em seguida não encontra
  # sessão conectada, então não vira alerta de queda nem sinal de IP ruim (#1516). Recusa do motor desfaz a pausa; sem
  # resposta (timeout), a pausa fica — o lado seguro é tudo pela oficial, e o administrador vê "Pausado" com o botão
  # de retomar.
  def pause!
    return @manager.refresh! if @connection.paused?

    previous_status = @connection.status
    @connection.update!(paused_at: Time.current, status: 'disconnected', down_alerted_at: nil)
    remote = @manager.fetch_remote
    @client.stop_session(@connection.session_name) if remote.present? && remote['status'] != 'STOPPED'
    @manager.refresh!
  rescue Waha::Client::Timeout
    @manager.refresh!
  rescue Waha::Client::Error
    @connection.update!(paused_at: nil, status: previous_status)
    raise
  end

  # Se o WhatsApp desvinculou o aparelho nesse meio-tempo, o motor pede QR e a aba mostra o fluxo de reconectar de
  # sempre. Sessão apagada no motor é recriada (com QR). Falha do motor mantém a pausa.
  def resume!
    paused_at = @connection.paused_at
    @connection.update!(paused_at: nil)
    remote = @manager.fetch_remote
    return @manager.ensure_session! if remote.blank?

    @client.start_session(@connection.session_name) if remote['status'] == 'STOPPED'
    @manager.refresh!
  rescue Waha::Client::Error
    @connection.update!(paused_at: paused_at || Time.current)
    raise
  end

  def qr
    @manager.qr
  end
end
