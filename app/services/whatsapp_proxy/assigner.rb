# Um IP da Webshare por número de WhatsApp não oficial (#1516). `for` devolve o proxy da sessão: o que já está
# atribuído, se continua válido na lista, ou um IP livre do Brasil (São Paulo primeiro). Nunca dois números no mesmo IP:
# a escolha roda sob trava do Postgres e o índice único no endereço segura o resto.
# nil = a sessão segue sem proxy (recurso desligado, sem chave, API fora, pool sem IP livre, ou proxy posto à mão fora
# da Webshare). O recurso só liga com WHATSAPP_PROXY_ENABLED=true: a chave da Webshare sozinha não basta.
# IP livre = fora da tabela E fora do que o próprio motor já usa (proxy posto à mão sem registro).
# A credencial só existe no Webshare::Proxy em memória: nada de usuário/senha em banco, Redis ou log.
class WhatsappProxy::Assigner
  LOCK_KEY = 1_516_000_001
  # Depois de falha da API ou pool esgotado, a atualização da aba não consulta a Webshare de novo por um tempo.
  BACKOFF_KEY = 'whatsapp_proxy:backoff'.freeze
  BACKOFF_TTL = 10.minutes.to_i
  SAO_PAULO_NAMES = %w[saopaulo saopaolo].freeze

  def self.listed(proxies, assignment)
    proxies.find { |proxy| proxy.valid? && proxy.address == assignment.proxy_address && proxy.port == assignment.proxy_port }
  end

  def self.feature_enabled?
    ENV.fetch('WHATSAPP_PROXY_ENABLED', 'false') == 'true'
  end

  def initialize(client: Webshare::Client.new, engine: Waha::Client.new)
    @client = client
    @engine = engine
  end

  def enabled?
    self.class.feature_enabled? && @client.configured?
  end

  # honor_backoff: só quem roda com frequência (atualização da aba) respeita a pausa; criar e reconectar sempre tentam.
  def for(session_name, honor_backoff: false)
    return unless self.class.feature_enabled?

    unless @client.configured?
      Rails.logger.warn("[whatsapp_proxy] WEBSHARE_API_KEY ausente: session=#{session_name} segue sem proxy")
      return
    end
    return if honor_backoff && backoff?

    resolve(session_name, @client.proxies)
  rescue Webshare::Client::Error => e
    backoff!
    Rails.logger.warn("[whatsapp_proxy] lista da Webshare indisponível (#{e.message}): session=#{session_name} segue sem proxy")
    nil
  end

  # Mesma decisão de `for`, com a lista já em mãos (a reconciliação busca a lista uma vez por rodada).
  def resolve(session_name, proxies)
    with_lock do
      assignment = WhatsappProxy::Assignment.find_by(session_name: session_name)
      if assignment&.external?
        nil
      else
        (assignment && self.class.listed(proxies, assignment)) || reassign(session_name, assignment, proxies)
      end
    end
  end

  # O motor recebeu este proxy: guarda o HMAC da credencial para notar troca de usuário/senha no mesmo IP.
  def mark_applied!(session_name, proxy)
    WhatsappProxy::Assignment.find_by(session_name: session_name, proxy_address: proxy.address)
                             &.update!(credential_digest: proxy.credential_digest)
  end

  # A sessão saiu do motor: o IP volta para o pool.
  def release!(session_name)
    WhatsappProxy::Assignment.where(session_name: session_name).delete_all
  end

  private

  def with_lock(&)
    WhatsappProxy::Assignment.transaction do
      WhatsappProxy::Assignment.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      yield
    end
  end

  def reassign(session_name, assignment, proxies)
    in_engine = engine_hosts(session_name)
    return if in_engine.nil?

    taken = WhatsappProxy::Assignment.where.not(session_name: session_name).pluck(:proxy_address) + in_engine
    candidate = pick(proxies.reject { |proxy| taken.include?(proxy.address) })
    return pool_exhausted!(session_name) if candidate.nil?

    record = assignment || WhatsappProxy::Assignment.new(session_name: session_name)
    log_reassign(session_name, assignment, candidate)
    record.update!(webshare_proxy_id: candidate.id, proxy_address: candidate.address, proxy_port: candidate.port,
                   assigned_at: Time.current, credential_digest: nil)
    candidate
  end

  # Hosts dos proxies que as outras sessões do motor já usam. Só o host: a credencial que o motor devolve é descartada.
  # Motor fora: nil, e nada é atribuído (sem a lista não dá para garantir IP livre).
  def engine_hosts(session_name)
    Array(@engine.list_sessions(all: true)).filter_map do |session|
      next if session['name'] == session_name

      proxy_host(session.dig('config', 'proxy', 'server'))
    end
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] motor não listou as sessões (#{e.class}): session=#{session_name} segue sem proxy")
    nil
  end

  def proxy_host(server)
    return if server.blank?

    server = server.to_s
    URI.parse(server.include?('://') ? server : "http://#{server}").host
  rescue URI::InvalidURIError
    nil
  end

  def pick(free)
    free.select { |proxy| proxy.valid? && proxy.country_code.casecmp?('BR') }
        .min_by { |proxy| [sao_paulo?(proxy) ? 0 : 1, proxy.id] }
  end

  # A Webshare escreve "Sao Paulo", "Sao Paolo" ou "São Paulo".
  def sao_paulo?(proxy)
    SAO_PAULO_NAMES.include?(ActiveSupport::Inflector.transliterate(proxy.city_name).downcase.delete(' '))
  end

  def log_reassign(session_name, assignment, candidate)
    if assignment
      Rails.logger.warn("[whatsapp_proxy] IP #{assignment.server} saiu da lista ou ficou inválido: session=#{session_name} " \
                        "passa para #{candidate.server}")
    else
      Rails.logger.info("[whatsapp_proxy] session=#{session_name} recebe #{candidate.server}")
    end
  end

  def pool_exhausted!(session_name)
    backoff!
    Rails.logger.error("[whatsapp_proxy] pool da Webshare sem IP livre no Brasil: session=#{session_name} segue sem proxy. " \
                       'Compre mais IPs no plano da Webshare.')
    nil
  end

  def backoff?
    ::Redis::Alfred.get(BACKOFF_KEY).present?
  rescue Redis::BaseError
    false
  end

  def backoff!
    ::Redis::Alfred.setex(BACKOFF_KEY, '1', BACKOFF_TTL)
  rescue Redis::BaseError
    nil
  end
end
