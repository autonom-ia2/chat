# Vazão do WhatsApp API por conexão (chat#1067). Dois baldes por minuto:
# - geral: `rate_limit_per_minute` da conexão;
# - campanha: no máximo CAMPAIGN_PER_MINUTE (campanha é a origem de maior risco).
# Os dois encolhem quando o WhatsApp avisa que o número está perto do limite (Capping).
class WhatsappHybrid::RateLimit
  WINDOW = 60
  CAMPAIGN_PER_MINUTE = 10

  def initialize(connection, origin)
    @connection = connection
    @origin = origin
  end

  def exceeded?
    factor = WhatsappHybrid::Capping.new(@connection).rate_factor
    return true if over?('all', limit(@connection.rate_limit_per_minute, factor))
    return false unless @origin == 'campaign'

    over?('campaign', limit([CAMPAIGN_PER_MINUTE, @connection.rate_limit_per_minute].min, factor))
  end

  private

  def limit(base, factor)
    [(base * factor).floor, 1].max
  end

  def over?(bucket, max)
    key = "whatsapp_hybrid:rate:#{@connection.id}:#{bucket}:#{Time.current.to_i / WINDOW}"
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, WINDOW * 2) if count == 1
    count > max
  end
end
