# O que UMA consulta a uma ferramenta assíncrona devolveu (#313).
#
# A ferramenta não conhece conversa nem mensagem: ela só diz "ainda estou", "acabei" ou "falhei", e
# entrega os textos que já servem ao cliente. Quem publica é o job.
#
# `deliveries` são textos DESTINADOS AO CLIENTE, escritos pela ferramenta a partir do que ela colheu.
# A ferramenta NUNCA tem canal para mandar erro ao cliente: falha se declara em `failure_code` (um
# código curto nosso) e o texto que o cliente lê é escrito pelo publicador. Isso preserva a fronteira
# que o `Bound` já defende hoje — mensagem de exceção pode carregar requisição assinada ou texto vindo
# do portal (`Insurance::Connector::Error#business_message` traz até 160 chars do AGGER), e nada disso
# pode chegar ao WhatsApp de um cliente.
class Autonomia::Agents::Tools::Progress
  MAX_DELIVERY_CHARS = 3_000
  MAX_DELIVERIES = 5

  attr_reader :status, :handle, :deliveries, :failure_code

  def self.running(deliveries: [], handle: nil)
    new(status: :running, deliveries: deliveries, handle: handle)
  end

  def self.done(deliveries: [], handle: nil)
    new(status: :done, deliveries: deliveries, handle: handle)
  end

  def self.failed(code, deliveries: [])
    new(status: :failed, deliveries: deliveries, failure_code: code)
  end

  def initialize(status:, deliveries: [], handle: nil, failure_code: nil)
    @status = status.to_sym
    @handle = handle
    @failure_code = sanitize_code(failure_code)
    @deliveries = sanitize(deliveries)
  end

  def running?
    status == :running
  end

  def done?
    status == :done
  end

  def failed?
    status == :failed
  end

  private

  # Corta o que não é texto útil e limita tamanho/quantidade. Não é sanitização de conteúdo (a
  # ferramenta é nossa e responde por ela), é o freio contra despejar um payload inteiro na conversa.
  def sanitize(list)
    Array(list).filter_map { |text| text.to_s.strip.presence }
               .first(MAX_DELIVERIES)
               .map { |text| ::Autonomia::Agents::Config.truncate_text(text, MAX_DELIVERY_CHARS) }
  end

  # Código curto e previsível (o mesmo cuidado de `Bound#http_error_code`): nunca deixa texto livre
  # de exceção virar identificador que depois vai parar em log ou métrica.
  def sanitize_code(code)
    value = code.to_s.strip.downcase.tr(' ', '_')
    return if value.blank?

    value.match?(/\A[a-z0-9_]{1,60}\z/) ? value : 'tool_failed'
  end
end
