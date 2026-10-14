# Limite temporário de conversas novas que o WhatsApp aplica aos aparelhos conectados do número (chat#1480).
# O motor informa em /timelock: isActive e timeEnforcementEnds (epoch em segundos). A sessão segue conectada;
# o que para é abrir conversa com quem ainda não conversa com o número. Guardamos o retrato para a aba mostrar.
class WhatsappHybrid::Timelock
  KEY_TTL = 2.days.to_i
  # A aba consulta a conexão a cada poucos segundos; o limite muda devagar.
  FRESH_FOR = 60.seconds

  def initialize(connection)
    @connection = connection
  end

  def current
    raw = ::Redis::Alfred.get(key)
    raw.present? ? JSON.parse(raw) : {}
  rescue JSON::ParserError
    {}
  end

  # Ativo no motor e ainda dentro do prazo (sem prazo informado, vale enquanto o motor disser que está ativo).
  def active?(snapshot = current)
    return false unless snapshot['active']

    snapshot['ends_at'].blank? || snapshot['ends_at'].to_i > Time.current.to_i
  end

  def fresh?
    current['checked_at'].to_i > FRESH_FOR.ago.to_i
  end

  # `data`: a resposta crua do motor (epoch em segundos em timeEnforcementEnds).
  def apply!(data)
    data = {} unless data.is_a?(Hash)
    write('active' => data['isActive'] == true, 'ends_at' => data['timeEnforcementEnds'])
  end

  # A consulta falhou: guarda só a hora da tentativa, sem mexer no último retrato.
  def checked!
    write(current.slice('active', 'ends_at'))
  end

  def payload
    snapshot = current
    active = active?(snapshot)
    { active: active, ends_at: active ? snapshot['ends_at'] : nil }
  end

  def key
    "whatsapp_hybrid:timelock:#{@connection.id}"
  end

  private

  def write(snapshot)
    ::Redis::Alfred.setex(key, snapshot.merge('checked_at' => Time.current.to_i).to_json, KEY_TTL)
  end
end
