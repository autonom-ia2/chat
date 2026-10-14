# Troca o proxy de uma sessão já existente no motor (WAHA comum ou Híbrido) — #1516. O motor reinicia a sessão ao
# receber a configuração nova, então a troca segue o padrão do backfill (Waha::ExistingInboxMigrationExecutor):
#   cópia da configuração atual → PUT só com `config` (sem a chave `apps`: o motor mantém os apps) → espera WORKING
#   (até ~3 min) com o MESMO número conectado (me.id, não o nome da sessão: números antigos sem o 9 diferem), a mesma
#   quantidade de apps e o proxy gravado. Falhou: regrava a configuração anterior e devolve :rolled_back.
# Sessão pedindo QR (aparelho desvinculado) ou parada (STOPPED, desligada de propósito) nunca é tocada: :refused.
# A configuração nova é a do motor com só o bloco `proxy` trocado (o motor guarda só as chaves que conhece).
# Leituras com timeout curto (READ_TIMEOUT), para o pior caso caber na trava do ApplyJob.
class WhatsappProxy::SessionUpdater
  VerificationError = Class.new(StandardError)
  WORKING = 'WORKING'.freeze
  UNTOUCHABLE = %w[SCAN_QR_CODE STOPPED].freeze
  HEALTH_ATTEMPTS = 36
  HEALTH_INTERVAL = 5
  READ_TIMEOUT = 8

  def initialize(client: Waha::Client.new, sleeper: ->(seconds) { sleep(seconds) },
                 health_attempts: HEALTH_ATTEMPTS, health_interval: HEALTH_INTERVAL)
    @client = client
    @sleeper = sleeper
    @health_attempts = health_attempts
    @health_interval = health_interval
  end

  # :applied quando o motor confirmou a troca; :rolled_back quando voltou à configuração anterior; :refused quando a
  # sessão não pode ser tocada.
  def apply!(session_name, proxy, before: nil)
    before ||= @client.get_session(session_name, timeout: READ_TIMEOUT)
    return refuse(session_name, before['status']) if UNTOUCHABLE.include?(before['status'].to_s)

    snapshot = { config: before['config'].to_h.deep_dup, me: me_id(before), apps: Array(@client.list_apps(session_name)).size }
    @client.update_session(session_name, config: snapshot[:config].merge('proxy' => proxy.to_session_config.stringify_keys))
    verify!(session_name, proxy, snapshot)
    :applied
  rescue Waha::Client::Error, VerificationError => e
    raise if snapshot.nil?

    rollback!(session_name, snapshot, e)
    :rolled_back
  end

  private

  def refuse(session_name, status)
    Rails.logger.warn("[whatsapp_proxy] session=#{session_name} em #{status}: troca de proxy recusada (não é o proxy)")
    :refused
  end

  def verify!(session_name, proxy, snapshot)
    current = wait_for_working!(session_name)
    raise VerificationError, 'number_changed' if snapshot[:me].present? && me_id(current) != snapshot[:me]
    raise VerificationError, 'apps_changed' if Array(@client.list_apps(session_name)).size != snapshot[:apps]
    raise VerificationError, 'proxy_not_saved' unless WhatsappProxy::Server.same?(current.dig('config', 'proxy', 'server'), proxy.server)
  end

  def wait_for_working!(session_name)
    @health_attempts.times do |attempt|
      current = @client.get_session(session_name, timeout: READ_TIMEOUT)
      return current if current['status'] == WORKING

      @sleeper.call(@health_interval) if attempt < @health_attempts - 1
    end
    raise VerificationError, 'session_did_not_return_to_working'
  end

  def rollback!(session_name, snapshot, error)
    reason = error.is_a?(VerificationError) ? error.message : error.class.name
    Rails.logger.warn("[whatsapp_proxy] troca de proxy desfeita session=#{session_name} (#{reason})")
    @client.update_session(session_name, config: snapshot[:config])
  rescue Waha::Client::Error => e
    WhatsappProxy::Alert.notify!('volta_falhou', "session=#{session_name}: a configuração anterior não foi regravada (#{e.class})",
                                 level: :error, session: session_name)
  end

  def me_id(session)
    session.dig('me', 'id').to_s.presence
  end
end
