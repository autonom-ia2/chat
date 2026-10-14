# Aplica no motor o proxy atribuído a uma sessão (#1516), agendado pela reconciliação ou pela atualização da aba do
# Híbrido. Recebe só o nome da sessão: a credencial vem de novo da API aqui dentro, para nunca passar pela fila (Redis).
# - Um job por sessão de cada vez: trava no Redis com token único, solta só por quem a pegou (compare-and-delete), com
#   TTL maior que o pior caso do SessionUpdater.
# - Antes do PUT confere o motor: proxy (host:porta) e credencial já iguais → só registra, sem PUT.
# - Troca desfeita pelo motor: a atribuição volta ao IP anterior (ou fica pendente), conta uma falha e entra em recuo
#   (10 min, 30 min, 2 h, 6 h, 24 h). Alerta `troca_desfeita` só na primeira falha e quando chega ao recuo máximo.
class WhatsappProxy::ApplyJob < ApplicationJob
  queue_as :low

  # Pior caso do SessionUpdater: 37 leituras de 8 s + 175 s de espera + PUT, apps e volta (20 s cada) ≈ 9 min.
  LOCK_TTL = 15.minutes.to_i

  def perform(session_name)
    token = SecureRandom.hex(16)
    return unless ::Redis::Alfred.set(lock_key(session_name), token, nx: true, ex: LOCK_TTL)

    begin
      apply(session_name)
    ensure
      ::Redis::Alfred.delete_if_equals(lock_key(session_name), token)
    end
  end

  def self.lock_key(session_name)
    "whatsapp_proxy:apply:#{session_name}"
  end

  private

  def lock_key(session_name)
    self.class.lock_key(session_name)
  end

  def apply(session_name)
    assigner = WhatsappProxy::Assigner.new
    proxy = assigner.for(session_name)
    return if proxy.nil?

    client = Waha::Client.new
    remote = client.get_session(session_name, timeout: WhatsappProxy::SessionUpdater::READ_TIMEOUT)
    return assigner.mark_applied!(session_name, proxy) if already_applied?(remote, proxy)

    outcome = WhatsappProxy::SessionUpdater.new(client: client).apply!(session_name, proxy, before: remote)
    return finished!(assigner, session_name, proxy) if outcome == :applied

    failed!(session_name, proxy) if outcome == :rolled_back
  rescue Waha::Client::NotFound
    Rails.logger.warn("[whatsapp_proxy] session=#{session_name} não existe no motor: atribuição liberada")
    assigner&.release!(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] troca de proxy falhou session=#{session_name}: #{e.class}")
    record_failure(session_name, &:apply_failed!)
  end

  def finished!(assigner, session_name, proxy)
    assigner.mark_applied!(session_name, proxy)
    Rails.logger.info("[whatsapp_proxy] session=#{session_name} agora sai por #{proxy.server}")
  end

  # O motor voltou à configuração anterior: a atribuição volta junto e entra em recuo.
  def failed!(session_name, proxy)
    assignment = record_failure(session_name, &:revert_failed_apply!)
    return if assignment.nil?
    return unless assignment.apply_failures == 1 || assignment.backoff_exhausted?

    WhatsappProxy::Alert.notify!('troca_desfeita', "troca de proxy da session=#{session_name} para #{proxy.server} desfeita " \
                                                   "(falha #{assignment.apply_failures}); nova tentativa com recuo",
                                 level: :error, session: session_name, ip: proxy.server, count: assignment.apply_failures)
  end

  # Volta da atribuição que bate em outra conta ou no limite do IP (raro: alguém pegou o IP antigo): fica pendente.
  def record_failure(session_name)
    WhatsappProxy::Assignment.exclusively do
      assignment = WhatsappProxy::Assignment.find_by(session_name: session_name)
      next if assignment.nil?

      yield assignment
      assignment
    rescue ActiveRecord::RecordInvalid
      assignment.reload.update!(proxy_address: nil, proxy_port: nil, webshare_proxy_id: nil, credential_digest: nil,
                                apply_failures: assignment.apply_failures + 1, last_apply_failed_at: Time.current)
      assignment
    end
  end

  def already_applied?(remote, proxy)
    return false unless WhatsappProxy::Server.same?(remote.dig('config', 'proxy', 'server'), proxy.server)

    remote_proxy = remote.dig('config', 'proxy')
    Webshare::Proxy.digest_for(remote_proxy['username'], remote_proxy['password']) == proxy.credential_digest
  end
end
