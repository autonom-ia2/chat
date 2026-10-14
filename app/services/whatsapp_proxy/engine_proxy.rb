# O proxy que o motor usa de fato numa sessão (#1516): host:porta normalizado e o HMAC da credencial. A credencial que o
# motor devolve em claro só vira HMAC aqui e é descartada.
module WhatsappProxy::EngineProxy
  module_function

  # [servidor, digest] de uma sessão já lida (GET ou item da lista); [nil, nil] sem proxy.
  def from_session(session)
    proxy = session.to_h.dig('config', 'proxy').to_h
    server = WhatsappProxy::Server.normalize(proxy['server'])
    return [nil, nil] if server.nil?

    [server, Webshare::Proxy.digest_for(proxy['username'], proxy['password'])]
  end

  # Credencial mascarada pelo motor (só asteriscos)? Aí o HMAC não diz nada: quem compara não regrava nem reaplica.
  def masked?(session)
    password = session.to_h.dig('config', 'proxy', 'password').to_s
    password.present? && password.delete('*').empty?
  end

  # Relê a sessão no motor (timeout curto); ilegível → [nil, nil].
  def read(client, session_name)
    from_session(client.get_session(session_name, timeout: WhatsappProxy::SessionUpdater::READ_TIMEOUT))
  rescue Waha::Client::Error
    [nil, nil]
  end
end
