# Proxy da Webshare por número de WhatsApp não oficial (#1516). Regra do Rodrigo (14/10):
# - o tipo da sessão escolhe o plano: Híbrido → isp (Static Residential), WAHA comum → datacenter; sempre IP do Brasil;
# - um IP por CONTA, até N números por IP (WHATSAPP_PROXY_MAX_NUMBERS_PER_IP, padrão 3): número novo reaproveita o IP da
#   conta que ainda tem vaga; senão pega um IP livre (São Paulo primeiro). Duas contas nunca no mesmo IP;
# - IP livre = da fatia desta stack, fora da tabela e fora do que o próprio motor já usa (proxy posto à mão sem registro);
# - número importado (proxy posto à mão) só muda de plano/conta com WHATSAPP_PROXY_AUTO_MIGRATE=true; IP morto se troca.
# `for` devolve o proxy da sessão ou nil (recurso desligado, sem chave, sessão sem dono, API ou motor fora, plano sem IP
# livre, proxy externo, erro inesperado). O recurso só liga com WHATSAPP_PROXY_ENABLED=true.
# A credencial só existe no Webshare::Proxy em memória: nada de usuário/senha em banco, Redis ou log.
class WhatsappProxy::Assigner
  SAO_PAULO_NAMES = %w[saopaulo saopaolo].freeze

  def self.feature_enabled?
    ENV.fetch('WHATSAPP_PROXY_ENABLED', 'false') == 'true'
  end

  # O IP atribuído continua servindo: na lista, válido, do Brasil e na fatia da stack.
  def self.listed(pool, assignment)
    pool.candidates.find { |proxy| proxy.address == assignment.proxy_address && proxy.port == assignment.proxy_port }
  end

  def initialize(engine: Waha::Client.new, pools: {})
    @engine = engine
    @pools = pools.transform_keys(&:to_s)
  end

  def pool(name)
    @pools[name.to_s] ||= WhatsappProxy::Pool.new(name)
  end

  def enabled?
    self.class.feature_enabled? && pool('isp').configured?
  end

  def for(session_name)
    return unless ready?(session_name)

    owner = WhatsappProxy::SessionOwner.find(session_name)
    return warn_nil('sessão sem caixa conhecida', session_name) if owner.nil?

    resolve(session_name, owner, pool(owner.pool))
  rescue Webshare::Client::Error => e
    warn_nil("lista da Webshare indisponível (#{e.message})", session_name)
  rescue StandardError => e
    warn_nil("falha inesperada (#{e.class})", session_name)
  end

  # Mesma decisão de `for`, com o dono já conhecido (a reconciliação busca cada plano uma vez por rodada).
  # Webshare e motor são consultados ANTES da trava; dentro dela só a tabela.
  def resolve(session_name, owner, pool)
    pool.proxies
    in_engine = engine_sessions(session_name)
    WhatsappProxy::Assignment.exclusively do
      assignment = WhatsappProxy::Assignment.find_by(session_name: session_name)
      next if assignment&.external?

      kept(assignment, owner) || reassign(session_name, owner, assignment, pool, in_engine)
    end
  end

  # O motor recebeu este proxy: guarda o HMAC da credencial (para notar troca de usuário/senha no mesmo IP) e zera o
  # recuo.
  def mark_applied!(session_name, proxy)
    WhatsappProxy::Assignment.find_by(session_name: session_name, proxy_address: proxy.address)&.applied!(proxy.credential_digest)
  end

  # Sessão nova que nasceu sem proxy porque a Webshare estava fora (#1516, M6): fica pendente e a reconciliação tenta
  # de novo, com recuo. Só com o recurso ligado e caixa conhecida; atribuição existente não muda.
  def mark_pending!(session_name)
    return unless enabled?

    owner = WhatsappProxy::SessionOwner.find(session_name)
    return if owner.nil? || WhatsappProxy::Assignment.exists?(session_name: session_name)

    WhatsappProxy::Assignment.create!(session_name: session_name, account_id: owner.account_id, pool: owner.pool,
                                      assigned_at: Time.current)
    WhatsappProxy::Alert.notify!('caixa_sem_proxy', "session=#{session_name} nasceu sem proxy: nova tentativa na reconciliação",
                                 session: session_name, pool: owner.pool)
  end

  # A sessão saiu do motor: o número deixa o IP (que volta ao plano quando não sobra número da conta nele).
  def release!(session_name)
    WhatsappProxy::Assignment.where(session_name: session_name).delete_all
  end

  private

  # Recurso desligado: nil calado (comportamento de antes). Ligado sem chave: nil com aviso.
  def ready?(session_name)
    return false unless self.class.feature_enabled?
    return true if pool('isp').configured?

    warn_nil('WEBSHARE_API_KEY ausente', session_name)
    false
  end

  # Fica onde está quando o IP ainda serve e o plano/conta batem — ou quando não batem, mas o número é importado e a
  # migração automática está desligada (aí vale o plano em que ele já está).
  def kept(assignment, owner)
    return if assignment.nil? || assignment.migratable_to?(owner)

    self.class.listed(pool(assignment.pool), assignment)
  end

  def reassign(session_name, owner, assignment, pool, in_engine)
    return if in_engine.nil?

    others = WhatsappProxy::Assignment.where.not(session_name: session_name)
    candidate = account_ip_with_room(owner, pool, others, in_engine) || free_ip(pool, others, in_engine)
    return pool_exhausted!(session_name, pool) if candidate.nil?

    log_reassign(session_name, assignment, candidate, pool)
    record = assignment || WhatsappProxy::Assignment.new(session_name: session_name)
    record.update!(previous_state(record).merge(
                     account_id: owner.account_id, pool: pool.name, origin: 'assigned', webshare_proxy_id: candidate.id,
                     proxy_address: candidate.address, proxy_port: candidate.port, assigned_at: Time.current, credential_digest: nil
                   ))
    candidate
  end

  # Guarda o IP que o motor tem agora, para voltar a ele se a troca for desfeita. Troca ainda não aplicada mantém o
  # anterior que já estava guardado.
  def previous_state(record)
    return {} if record.pending? || record.previous_proxy_address.present?

    { previous_proxy_address: record.proxy_address, previous_proxy_port: record.proxy_port,
      previous_webshare_proxy_id: record.webshare_proxy_id, previous_credential_digest: record.credential_digest }
  end

  # IP da própria conta (mesmo plano) com menos de N números; o mais cheio primeiro, para usar menos IPs. Fora: IP que
  # o motor mostra numa sessão que não é desta conta neste IP (proxy posto à mão sem registro).
  def account_ip_with_room(owner, pool, others, in_engine)
    mine = others.where(account_id: owner.account_id, pool: pool.name)
    counts = mine.group(:proxy_address).count
    known = mine.pluck(:session_name, :proxy_address)
    foreign = in_engine.reject { |pair| known.include?(pair) }.map(&:last)
    max = WhatsappProxy::Assignment.max_numbers_per_ip
    pool.candidates.select { |proxy| counts.fetch(proxy.address, max) < max && foreign.exclude?(proxy.address) }
        .max_by { |proxy| [counts[proxy.address], proxy.address] }
  end

  def free_ip(pool, others, in_engine)
    taken = others.distinct.pluck(:proxy_address) + in_engine.map(&:last)
    pool.candidates.reject { |proxy| taken.include?(proxy.address) }
        .min_by { |proxy| [sao_paulo?(proxy) ? 0 : 1, proxy.id] }
  end

  # [nome, host] das outras sessões do motor que têm proxy. Só o host: a credencial que o motor devolve é descartada.
  # Motor fora: nil, e nada é atribuído de novo (sem a lista não dá para garantir IP livre).
  def engine_sessions(session_name)
    Array(@engine.list_sessions(all: true)).filter_map do |session|
      next if session['name'] == session_name

      host = WhatsappProxy::Server.host(session.dig('config', 'proxy', 'server'))
      [session['name'], host] if host
    end
  rescue Waha::Client::Error => e
    warn_nil("motor não listou as sessões (#{e.class})", session_name)
  end

  # A Webshare escreve "Sao Paulo", "Sao Paolo" ou "São Paulo".
  def sao_paulo?(proxy)
    SAO_PAULO_NAMES.include?(ActiveSupport::Inflector.transliterate(proxy.city_name).downcase.delete(' '))
  end

  def log_reassign(session_name, assignment, candidate, pool)
    if assignment
      Rails.logger.warn("[whatsapp_proxy] session=#{session_name} sai de #{assignment.server} (#{assignment.pool}) " \
                        "para #{candidate.server} (#{pool.name})")
    else
      Rails.logger.info("[whatsapp_proxy] session=#{session_name} recebe #{candidate.server} (#{pool.name})")
    end
  end

  # Fatia vazia já alertou `fatia_vazia`: não é "plano esgotado".
  def pool_exhausted!(session_name, pool)
    return if pool.slice.empty?

    WhatsappProxy::Alert.notify!('plano_esgotado', "plano #{pool.name} sem IP do Brasil livre na fatia desta stack: " \
                                                   "session=#{session_name} segue sem proxy. Compre mais IPs ou amplie a fatia.",
                                 level: :error, session: session_name, pool: pool.name)
    nil
  end

  def warn_nil(reason, session_name)
    Rails.logger.warn("[whatsapp_proxy] #{reason}: session=#{session_name} segue sem proxy")
    nil
  end
end
