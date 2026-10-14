# Falha geral ou IP ruim? (#1516) Se a Webshare inteira cair, o WhatsApp Web cair ou o motor reiniciar, todas as
# sessões saem de WORKING ao mesmo tempo — tratar cada uma como "IP instável" queimaria o plano em quarentena e
# reiniciaria dezenas de números à toa.
#
# Mede QUEDA RECENTE, não estado: só conta a sessão que estava WORKING na rodada anterior e agora está fora (STARTING ou
# FAILED). Sessão que já estava fora antes não entra nem na conta nem no denominador. O status da rodada anterior fica
# no Redis (PREVIOUS_TTL); sem ele, `known?` é false: não há falha geral e a reconciliação não troca por instabilidade.
#
# Começa uma falha geral (alerta `falha_geral`) quando, entre os que estavam WORKING:
# - plano: mais de MAX_SHARE dos IPs em uso caíram (por IP), com pelo menos MIN_OFF IPs; ou
# - linha de base: mais de MAX_SHARE das sessões SEM nenhum proxy caíram, com pelo menos MIN_OFF e só com pelo menos
#   MIN_BASELINE sessões que estavam WORKING (poucas sessões não são linha de base) — vale para todos os planos.
# Continua (sem prazo) enquanto as que caíram seguem fora acima do mesmo limite — falha geral longa não vira "IP
# instável" por tempo. Termina quando a maioria voltou (alerta `falha_geral_fim`, um por episódio); as que seguem fora
# passam a ser avaliadas uma a uma, do zero, a partir da rodada SEGUINTE (WhatsappProxy::Health.eligible!). Na rodada
# em que um episódio termina, não abre outro no mesmo escopo.
class WhatsappProxy::Outage
  MAX_SHARE = 0.3
  MIN_OFF = 2
  MIN_BASELINE = 5
  PREVIOUS_KEY = 'whatsapp_proxy:previous_statuses'.freeze
  PREVIOUS_TTL = 30.minutes.to_i
  EPISODE_TTL = 20.minutes.to_i
  ALERT_WINDOW = 1.day
  BASELINE = 'baseline'.freeze
  SCOPES = [BASELINE, *WhatsappProxy::Assignment::POOLS].freeze

  def self.previous
    raw = ::Redis::Alfred.get(PREVIOUS_KEY)
    raw.present? ? JSON.parse(raw) : nil
  rescue Redis::BaseError, JSON::ParserError
    nil
  end

  def self.remember!(engine_sessions)
    statuses = engine_sessions.to_h { |session| [session['name'], session['status'].to_s] }
    ::Redis::Alfred.setex(PREVIOUS_KEY, statuses.to_json, PREVIOUS_TTL)
  rescue Redis::BaseError
    nil
  end

  # Há falha geral em curso para este plano (o webhook do Híbrido usa para não contar quedas)?
  def self.active?(pool)
    [pool.to_s, BASELINE].any? { |scope| ::Redis::Alfred.get(episode_key(scope)).present? }
  rescue Redis::BaseError
    false
  end

  def self.episode_key(scope)
    "whatsapp_proxy:outage:#{scope}"
  end

  # engine_sessions: o GET /api/sessions?all=true; assignments: as atribuições; previous: status da rodada anterior.
  def initialize(engine_sessions, assignments, previous:)
    @engine_sessions = engine_sessions
    @assignments = assignments
    @previous = previous
    @statuses = engine_sessions.to_h { |session| [session['name'], session['status'].to_s] }
    @episodes = {}
    @just_ended = []
  end

  # Sessões cujo episódio terminou nesta rodada: não contam nesta rodada.
  def just_ended?(session_name)
    @just_ended.include?(session_name)
  end

  def known?
    !@previous.nil?
  end

  def previous_status(session_name)
    @previous&.dig(session_name)
  end

  # Avalia todos os escopos uma vez na rodada (começo, continuação e fim de episódio, com os alertas).
  def evaluate!
    SCOPES.each { |scope| episode?(scope) } if known?
  end

  def general?(pool)
    known? && (episode?(BASELINE) || episode?(pool.to_s))
  end

  private

  def episode?(scope)
    return @episodes[scope] if @episodes.key?(scope)

    episode = stored_episode(scope)
    @episodes[scope] = episode ? continue_or_finish(scope, episode) : start?(scope)
  end

  def start?(scope)
    dropped, total = drop_numbers(scope)
    return false if scope == BASELINE && total < MIN_BASELINE
    return false unless dropped >= MIN_OFF && dropped > total * MAX_SHARE

    episode_id = "#{scope}:#{Time.current.to_i}"
    store_episode(scope, 'id' => episode_id, 'members' => dropped_sessions(scope))
    WhatsappProxy::Alert.notify!('falha_geral', "#{dropped} de #{total} (#{scope}) que estavam WORKING caíram juntos: falha " \
                                                'geral, nada trocado nem posto em quarentena',
                                 level: :error, pool: scope, count: dropped, total: total, subject: episode_id, window: ALERT_WINDOW)
    true
  end

  def continue_or_finish(scope, episode)
    members = Array(episode['members'])
    still_off = members.select { |name| off?(name) }
    if still_off.size >= MIN_OFF && still_off.size > members.size * MAX_SHARE
      store_episode(scope, episode)
      return true
    end

    finish!(scope, episode, still_off)
  end

  def finish!(scope, episode, still_off)
    still_off.each { |name| WhatsappProxy::Health.eligible!(name) }
    @just_ended.concat(still_off)
    ::Redis::Alfred.delete(self.class.episode_key(scope))
    WhatsappProxy::Alert.notify!('falha_geral_fim', "falha geral (#{scope}) terminou; #{still_off.size} sessão(ões) ainda fora",
                                 pool: scope, count: still_off.size, subject: episode['id'], window: ALERT_WINDOW)
    false
  rescue Redis::BaseError
    false
  end

  # [caíram, estavam WORKING]: por IP num plano, por sessão na linha de base.
  def drop_numbers(scope)
    return session_drop_numbers(baseline_sessions) if scope == BASELINE

    ips = pool_sessions(scope).group_by(&:proxy_address)
    was_working = ips.select { |_address, rows| rows.any? { |row| working_before?(row.session_name) } }
    [was_working.count { |_address, rows| rows.any? { |row| dropped?(row.session_name) } }, was_working.size]
  end

  def session_drop_numbers(names)
    was_working = names.select { |name| working_before?(name) }
    [was_working.count { |name| dropped?(name) }, was_working.size]
  end

  def dropped_sessions(scope)
    names = scope == BASELINE ? baseline_sessions : pool_sessions(scope).map(&:session_name)
    names.select { |name| dropped?(name) }
  end

  def pool_sessions(pool)
    @assignments.select { |assignment| assignment.pool == pool && !assignment.pending? && @statuses.key?(assignment.session_name) }
  end

  # Sessões sem nenhum proxy (nem nosso, nem antigo): o WhatsApp e o motor sem a Webshare no meio.
  def baseline_sessions
    @baseline_sessions ||= begin
      proxied = @assignments.reject(&:pending?).map(&:session_name)
      @engine_sessions.reject { |session| proxied.include?(session['name']) || session.dig('config', 'proxy', 'server').present? }
                      .pluck('name')
    end
  end

  def working_before?(name)
    previous_status(name) == 'WORKING'
  end

  def dropped?(name)
    working_before?(name) && off?(name)
  end

  def off?(name)
    WhatsappProxy::Health::UNSTABLE_STATUSES.include?(@statuses[name])
  end

  def stored_episode(scope)
    raw = ::Redis::Alfred.get(self.class.episode_key(scope))
    raw.present? ? JSON.parse(raw) : nil
  rescue Redis::BaseError, JSON::ParserError
    nil
  end

  def store_episode(scope, episode)
    ::Redis::Alfred.setex(self.class.episode_key(scope), episode.to_json, EPISODE_TTL)
  rescue Redis::BaseError
    nil
  end
end
