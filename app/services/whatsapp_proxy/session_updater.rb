# Troca o proxy de uma sessão WAHA comum já existente (#1516), preservando o resto da configuração e os apps
# (conector de mensagens e números brasileiros). O motor reinicia a sessão ao receber a configuração nova: só a
# reconciliação chama isto, com limite por rodada. Sessões do Híbrido usam WhatsappHybrid::SessionManager#apply_proxy!.
class WhatsappProxy::SessionUpdater
  def initialize(client: Waha::Client.new)
    @client = client
  end

  def apply!(session_name, proxy)
    remote = @client.get_session(session_name)
    config = remote['config'].to_h.merge('proxy' => proxy.to_session_config.stringify_keys)
    @client.update_session(session_name, config: config, apps: Array(@client.list_apps(session_name)))
  end
end
