# Onde fica a ação do dia escrita pela IA (#1100, F4a). Redis, sem tabela.
#
# A chave junta conta, período, dia (no fuso da conta de anúncios), idioma e a assinatura dos números que mudam a
# ação: a ação da regra (sem o título dos cards), o veredito de cada anúncio, propostas, vendas e a confiança.
# O gasto fica de fora: ele muda a cada leitura da Meta e faria a IA rodar de novo a cada 30 minutos.
#
# Vale até o fim do dia (no mínimo 1 h). Falha do provedor fica guardada 15 min, para não martelar o provedor.
# Teto de DAILY_LIMIT gerações por conta por dia; passado o teto, vale o último texto do dia ou a regra.
class Crm::MetaAds::Panel::AiActionCache
  PREFIX = 'crm:meta_ads:daily_action:v1'.freeze
  DAILY_LIMIT = 6
  MIN_TTL = 1.hour
  ERROR_TTL = 15.minutes
  COUNTER_TTL = 36.hours

  def initialize(connection:, report:, zone:, locale:)
    @connection = connection
    @report = report
    @zone = zone
    @locale = locale.to_s
  end

  def read
    parse(Redis::Alfred.get(key))
  end

  # O guardado, ou o que o bloco gerar (que passa a ser o guardado).
  def fetch
    read || write(yield)
  end

  def write(result)
    ai_error = result[:reason] == 'ai_error'
    Redis::Alfred.set(key, result.to_json, ex: (ai_error ? ERROR_TTL : day_ttl).to_i)
    Redis::Alfred.set(last_key, result.to_json, ex: day_ttl.to_i) if result[:source] == 'ai'
    result
  end

  # Reserva uma geração do dia. false quando a conta já passou do teto.
  def reserve!
    count = Redis::Alfred.incr(counter_key)
    Redis::Alfred.expire(counter_key, COUNTER_TTL.to_i) if count == 1
    count <= DAILY_LIMIT
  end

  # Passou do teto: o último texto da IA do dia, se houver.
  def last
    parse(Redis::Alfred.get(last_key))
  end

  def signature
    action = @report[:action].to_h
    cards = Array(action[:cards]).map { |card| card.except(:title) }
    data = {
      action: action.except(:cards).merge(cards: cards),
      ads: Array(@report[:ads]).map { |ad| [ad[:ad_id], ad[:verdict]] },
      totals: @report[:totals].to_h.slice(:quotes, :open_quotes, :sales),
      confidence: @report[:confidence].to_h.slice(:conversations, :ad, :ad_name)
    }
    Digest::SHA256.hexdigest(data.to_json)
  end

  private

  def day
    @day ||= Time.current.in_time_zone(@zone).to_date
  end

  def scope
    "#{PREFIX}:#{@connection.account_id}:#{@report[:days]}:#{day.iso8601}:#{@locale}"
  end

  def key
    "#{scope}:#{signature}"
  end

  def last_key
    "#{scope}:last"
  end

  def counter_key
    "#{PREFIX}:count:#{@connection.account_id}:#{day.iso8601}"
  end

  def day_ttl
    [day.in_time_zone(@zone).end_of_day - Time.current, MIN_TTL].max
  end

  def parse(value)
    JSON.parse(value).deep_symbolize_keys if value.present?
  end
end
