# Aplica no motor o proxy atribuído a uma sessão (#1516), agendado pela reconciliação ou pela atualização da aba do
# Híbrido. Recebe só o nome da sessão: a credencial vem de novo da API aqui dentro, para nunca passar pela fila (Redis).
# Um job por sessão de cada vez (trava curta no Redis). Antes do PUT confere o motor: se o proxy gravado já é o
# atribuído (host:porta) e a credencial aplicada não mudou, não faz nada. A troca em si (com espera e volta) é do
# WhatsappProxy::SessionUpdater. Falha do motor não é repetida aqui: a próxima rodada da reconciliação reagenda.
class WhatsappProxy::ApplyJob < ApplicationJob
  queue_as :low

  # Cobre a espera do SessionUpdater (~3 min) com folga.
  LOCK_TTL = 5.minutes.to_i

  def perform(session_name)
    return unless lock(session_name)

    apply(session_name)
  ensure
    unlock(session_name)
  end

  private

  def apply(session_name)
    assigner = WhatsappProxy::Assigner.new
    proxy = assigner.for(session_name)
    return if proxy.nil?

    client = Waha::Client.new
    remote = client.get_session(session_name)
    return assigner.mark_applied!(session_name, proxy) if already_applied?(session_name, remote, proxy)
    return unless WhatsappProxy::SessionUpdater.new(client: client).apply!(session_name, proxy, before: remote)

    assigner.mark_applied!(session_name, proxy)
    Rails.logger.info("[whatsapp_proxy] session=#{session_name} agora sai por #{proxy.server}")
  rescue Waha::Client::NotFound
    Rails.logger.warn("[whatsapp_proxy] session=#{session_name} não existe no motor: atribuição liberada")
    assigner&.release!(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] troca de proxy falhou session=#{session_name}: #{e.class}")
  end

  def already_applied?(session_name, remote, proxy)
    return false unless WhatsappProxy::Server.same?(remote.dig('config', 'proxy', 'server'), proxy.server)

    remote_proxy = remote.dig('config', 'proxy')
    digest = Webshare::Proxy.digest_for(remote_proxy['username'], remote_proxy['password'])
    digest == proxy.credential_digest && WhatsappProxy::Assignment.exists?(session_name: session_name)
  end

  def lock_key(session_name)
    "whatsapp_proxy:apply:#{session_name}"
  end

  def lock(session_name)
    @locked = ::Redis::Alfred.set(lock_key(session_name), '1', nx: true, ex: LOCK_TTL)
  end

  def unlock(session_name)
    ::Redis::Alfred.delete(lock_key(session_name)) if @locked
  end
end
