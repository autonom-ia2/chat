# O que UMA consulta a uma ferramenta assíncrona devolveu (#313).
#
# A ferramenta não conhece conversa nem mensagem: ela só diz "ainda estou", "acabei" ou "falhei", e
# entrega os textos que já servem ao cliente. Quem publica é o job.
#
# `deliveries` são textos DESTINADOS AO CLIENTE, escritos pela ferramenta a partir do que ela colheu
# — ou, desde a entrega 11, um ARQUIVO para o cliente (`EntregaDeArquivo`, na forma serializada:
# a URL de onde o publicador baixa, o nome, a legenda e o texto de reserva com o link).
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
  #
  # E DESCARTA CAMINHO DE CAMPO. Em 08/09/2026 uma entrega levou `insured.document` ao WhatsApp de
  # um cliente: a ferramenta pôs no canal do cliente um texto que era para o modelo. O contrato
  # acima já dizia que isso não podia; faltava quem o fizesse valer. Descarta a ENTREGA, nunca
  # derruba a execução — perder uma frase é ruim, perder a cotação inteira é pior.
  def sanitize(list)
    Array(list).filter_map { |entrega| entrega.is_a?(String) ? texto(entrega) : arquivo(entrega) }
               .first(MAX_DELIVERIES)
  end

  def texto(valor)
    text = valor.to_s.strip.presence
    return if text.nil? || caminho_de_campo?(text)

    ::Autonomia::Agents::Config.truncate_text(text, MAX_DELIVERY_CHARS)
  end

  # A entrega de arquivo passa pela MESMA peneira nos dois textos dela (a legenda que sai com o
  # arquivo e a reserva que sai no lugar dele), e sai na forma serializada — é assim que ela chega
  # ao handle e ao job. O que não é texto nem entrega de arquivo (um Hash qualquer) não passa.
  def arquivo(valor)
    entrega = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(valor)
    return descartar('entrega que não é texto nem arquivo') if entrega.nil?

    legenda = texto(entrega.legenda)
    reserva = texto(entrega.reserva)
    return if legenda.nil? || reserva.nil?

    ::Autonomia::Agents::Tools::EntregaDeArquivo.new(url: entrega.url, nome: entrega.nome,
                                                     legenda: legenda, reserva: reserva).to_h
  end

  def descartar(motivo)
    Rails.logger.warn("[autonomia][tool] entrega descartada: #{motivo}")
    nil
  end

  # `a.b` sem espaço entre dois identificadores é assinatura de caminho de campo; frase em português
  # tem espaço depois do ponto. URL SAI ANTES DE OLHAR: o comparativo em PDF é uma entrega legítima
  # e o host dela casaria com o padrão — guarda que come o comparativo troca um bug de texto por um
  # entregável perdido.
  CAMINHO_DE_CAMPO = /\b[a-z][a-z0-9]*\.[a-z][a-zA-Z0-9]*\b/
  URL = %r{https?://\S+}

  def caminho_de_campo?(text)
    return false unless text.gsub(URL, ' ').match?(CAMINHO_DE_CAMPO)

    descartar('caminho de campo em texto de cliente')
    true
  end

  # Código curto e previsível (o mesmo cuidado de `Bound#http_error_code`): nunca deixa texto livre
  # de exceção virar identificador que depois vai parar em log ou métrica.
  def sanitize_code(code)
    value = code.to_s.strip.downcase.tr(' ', '_')
    return if value.blank?

    value.match?(/\A[a-z0-9_]{1,60}\z/) ? value : 'tool_failed'
  end
end
