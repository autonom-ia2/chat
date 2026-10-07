# Contadores do WhatsApp Híbrido por dia, origem e resultado (chat#1067, "medir na prática").
# Redis: um hash por conexão e dia ("<origem>:<resultado>" => n), guardado por 9 dias.
module WhatsappHybrid::Stats
  ORIGINS = WhatsappHybrid::Connection::ORIGINS
  OUTCOMES = %w[sent failed uncertain throttled disconnected fallback].freeze
  DAYS = 7
  TTL = 9.days.to_i

  module_function

  def record(connection, origin:, outcome:)
    key = key_for(connection, Time.zone.today)
    ::Redis::Alfred.with do |redis|
      redis.hincrby(key, "#{origin}:#{outcome}", 1)
      redis.expire(key, TTL)
    end
  rescue StandardError => e
    # Contar nunca pode derrubar um envio.
    Rails.logger.warn("[whatsapp_hybrid] stats record failed connection=#{connection.id}: #{e.class}")
  end

  # { 'human' => { 'sent' => 3, ... }, ... } somando os últimos DAYS dias (hoje incluso).
  def summary(connection, today: Time.zone.today)
    totals = ORIGINS.index_with { OUTCOMES.index_with { 0 } }
    ((today - (DAYS - 1))..today).each do |day|
      ::Redis::Alfred.with { |redis| redis.hgetall(key_for(connection, day)) }.each do |field, count|
        origin, outcome = field.split(':', 2)
        totals[origin][outcome] += count.to_i if totals.dig(origin, outcome)
      end
    end
    totals
  end

  def key_for(connection, day)
    "whatsapp_hybrid:stats:#{connection.id}:#{day.iso8601}"
  end
end
