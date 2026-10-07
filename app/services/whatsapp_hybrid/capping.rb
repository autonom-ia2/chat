# Limite de conversas novas do WhatsApp para o número (chat#1067). O WAHA informa o estado no evento
# session.status e no endpoint /capping: NONE, FIRST_WARNING, SECOND_WARNING, CAPPED (conjunto aberto).
# Avisos reduzem a vazão do WhatsApp API sozinhos; CAPPED bloqueia conversas novas até o fim do ciclo.
class WhatsappHybrid::Capping
  KEY_TTL = 40.days.to_i
  WARNINGS = %w[FIRST_WARNING SECOND_WARNING CAPPED].freeze
  # Fração da vazão configurada que continua valendo em cada estado.
  RATE_FACTOR = { 'FIRST_WARNING' => 0.5, 'SECOND_WARNING' => 0.25, 'CAPPED' => 0.25 }.freeze

  def initialize(connection)
    @connection = connection
  end

  def current
    raw = ::Redis::Alfred.get(key)
    raw.present? ? JSON.parse(raw) : {}
  rescue JSON::ParserError
    {}
  end

  def status
    current['status'].presence || 'NONE'
  end

  def rate_factor
    RATE_FACTOR.fetch(status, 1.0)
  end

  # `data`: o messageCapping cru do motor. Grava e avisa os administradores uma vez por estado e ciclo.
  def apply!(data)
    return if data.blank?

    previous = status
    snapshot = {
      'status' => data['cappingStatus'].to_s, 'used' => data['usedQuota'], 'total' => data['totalQuota'],
      'cycle_start' => data['cycleStart'], 'cycle_end' => data['cycleEnd'], 'checked_at' => Time.current.to_i
    }
    ::Redis::Alfred.setex(key, snapshot.to_json, KEY_TTL)
    alert!(snapshot) if snapshot['status'] != previous && WARNINGS.include?(snapshot['status'])
  end

  def key
    "whatsapp_hybrid:capping:#{@connection.id}"
  end

  private

  def alert!(snapshot)
    Autonomia::Guide::Entrega.new(@connection.account).whatsapp_api_limite!(
      @connection.inbox, snapshot['status'], snapshot['cycle_start'], snapshot['cycle_end']
    )
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] capping alert failed inbox=#{@connection.inbox_id}: #{e.class}")
  end
end
