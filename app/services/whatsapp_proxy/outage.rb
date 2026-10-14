# Falha geral ou IP ruim? (#1516) Se a Webshare inteira cair, o WhatsApp Web cair ou o motor reiniciar, todas as
# sessões saem de WORKING ao mesmo tempo — tratar cada uma como "IP instável" queimaria o plano em quarentena e
# reiniciaria dezenas de números à toa.
#
# Mede QUEDA RECENTE, não estado: só conta a sessão que estava WORKING na rodada anterior e agora está fora (STARTING ou
# FAILED). Sessão que já estava fora antes (FAILED há dias, como as da Autonom.ia em 14/10/2026) não entra nem na conta
# nem no denominador. O status da rodada anterior fica no Redis (PREVIOUS_TTL); sem ele (primeira rodada, Redis vazio
# ou fora), `known?` é false: não há falha geral e a reconciliação não troca por instabilidade — só observa.
#
# Começa uma falha geral quando, entre os que estavam WORKING:
# - plano: mais de MAX_SHARE dos IPs em uso caíram (por IP: um IP ruim leva até 3 números e ainda é um IP), com pelo
#   menos MIN_OFF IPs; ou
# - linha de base: mais de MAX_SHARE das sessões SEM proxy do motor caíram, com pelo menos MIN_OFF — vale para todos os
#   planos. Sessão com proxy que não é nosso (proxy rotativo antigo, sem atribuição) fica fora da linha de base.
# A falha geral continua enquanto a maioria das sessões que caíram no começo segue fora (lista no Redis, EPISODE_TTL
# renovado a cada rodada): sem isso, na rodada seguinte elas já não "estavam WORKING" e virariam IP instável.
class WhatsappProxy::Outage
  MAX_SHARE = 0.3
  MIN_OFF = 2
  PREVIOUS_KEY = 'whatsapp_proxy:previous_statuses'.freeze
  PREVIOUS_TTL = 30.minutes.to_i
  EPISODE_TTL = 20.minutes.to_i
  BASELINE = 'baseline'.freeze

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

  # engine_sessions: o GET /api/sessions?all=true; assignments: as atribuições da Webshare; previous: status da rodada
  # anterior (nil quando desconhecido).
  def initialize(engine_sessions, assignments, previous:)
    @engine_sessions = engine_sessions
    @assignments = assignments
    @previous = previous
    @statuses = engine_sessions.to_h { |session| [session['name'], session['status'].to_s] }
    @episodes = {}
  end

  def known?
    !@previous.nil?
  end

  def general?(pool)
    known? && (episode?(BASELINE) || episode?(pool.to_s))
  end

  # [caíram, estavam WORKING] para o alerta.
  def numbers(pool)
    episode?(BASELINE) ? drop_numbers(baseline_sessions) : ip_drop_numbers(pool.to_s)
  end

  private

  def episode?(scope)
    return @episodes[scope] if @episodes.key?(scope)

    @episodes[scope] = started?(scope) || continuing?(scope)
  end

  def started?(scope)
    dropped, total = scope == BASELINE ? drop_numbers(baseline_sessions) : ip_drop_numbers(scope)
    return false unless dropped >= MIN_OFF && dropped > total * MAX_SHARE

    store_episode(scope, dropped_sessions(scope))
    true
  end

  def continuing?(scope)
    members = stored_episode(scope)
    still_off = members.count { |name| off?(name) }
    return false unless still_off >= MIN_OFF && still_off > members.size * MAX_SHARE

    store_episode(scope, members)
    true
  end

  # Por IP: IPs com ao menos uma sessão WORKING na rodada anterior; caídos = os que têm uma dessas agora fora.
  def ip_drop_numbers(pool)
    ips = pool_sessions(pool).group_by(&:proxy_address)
    was_working = ips.select { |_address, rows| rows.any? { |row| working_before?(row.session_name) } }
    dropped = was_working.count { |_address, rows| rows.any? { |row| dropped?(row.session_name) } }
    [dropped, was_working.size]
  end

  def drop_numbers(names)
    was_working = names.select { |name| working_before?(name) }
    [was_working.count { |name| dropped?(name) }, was_working.size]
  end

  def dropped_sessions(scope)
    names = scope == BASELINE ? baseline_sessions : pool_sessions(scope).map(&:session_name)
    names.select { |name| dropped?(name) }
  end

  def pool_sessions(pool)
    @assignments.select { |assignment| assignment.pool == pool && @statuses.key?(assignment.session_name) }
  end

  # Sessões sem nenhum proxy (nem nosso, nem antigo): o WhatsApp e o motor sem a Webshare no meio.
  def baseline_sessions
    @baseline_sessions ||= begin
      proxied = @assignments.map(&:session_name)
      @engine_sessions.reject { |session| proxied.include?(session['name']) || session.dig('config', 'proxy', 'server').present? }
                      .pluck('name')
    end
  end

  def working_before?(name)
    @previous&.dig(name) == 'WORKING'
  end

  def dropped?(name)
    working_before?(name) && off?(name)
  end

  def off?(name)
    WhatsappProxy::Health::UNSTABLE_STATUSES.include?(@statuses[name])
  end

  def stored_episode(scope)
    raw = ::Redis::Alfred.get(self.class.episode_key(scope))
    raw.present? ? Array(JSON.parse(raw)) : []
  rescue Redis::BaseError, JSON::ParserError
    []
  end

  def store_episode(scope, members)
    ::Redis::Alfred.setex(self.class.episode_key(scope), members.to_json, EPISODE_TTL)
  rescue Redis::BaseError
    nil
  end
end
