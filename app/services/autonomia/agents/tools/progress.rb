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

  # UMA ENTREGA, NA FORMA EM QUE ELA VAI SAIR — texto depurado, entrega de arquivo depurada nos dois
  # textos dela, ou nil quando não sobrou nada que se possa publicar.
  #
  # PÚBLICA PORQUE A FERRAMENTA PRECISA DA MESMA RESPOSTA ANTES DE GRAVAR (12/09/2026). A identidade
  # de uma entrega é o SHA do texto FINAL, e até aqui a ferramenta calculava o token sobre o texto
  # CRU e só depois o `Progress` aparava e cortava: dois textos, dois tokens, e o fecho perguntando
  # por uma mensagem que nunca existiu. Agora a ferramenta chama isto, calcula o token sobre o que
  # volta e só então avança o handle; a segunda passada por aqui não muda mais nada, porque
  # `TextoAoCliente.depurar` é idempotente.
  def self.entregavel(valor)
    valor.is_a?(String) ? texto(valor) : arquivo(valor)
  end

  # Apara, troca travessão por hífen, redige caminho de campo que tenha escapado e corta no teto.
  # NÃO DESCARTA POR CONTEÚDO — e essa é a mudança de 12/09/2026. A peneira que descartava a entrega
  # inteira nasceu contra o texto do CÓDIGO (em 08/09 um cliente leu `insured.document` no
  # WhatsApp), e passou a valer para uma entrega que é "abertura + dezessete preços + aviso" numa
  # string só: descartá-la deixava o handle já avançado, as ofertas nunca mais eram reemitidas, e o
  # cliente lia a frase de falha sobre dezessete seguradoras que a corretora pagou. Quem barra o
  # texto de FORA (a frase que o modelo escreveu) é `TextoAoCliente.vetar`, na LEITURA do parâmetro,
  # onde recuar custa uma frase e não a cotação.
  def self.texto(valor)
    ::Autonomia::Agents::Tools::TextoAoCliente.depurar(valor, teto: MAX_DELIVERY_CHARS)
  end

  # A entrega de arquivo passa pela MESMA depuração nos dois textos dela (a legenda que sai com o
  # arquivo e a reserva que sai no lugar dele), e sai na forma serializada — é assim que ela chega
  # ao handle e ao job. O que não é texto nem entrega de arquivo (um Hash qualquer) não passa: aí
  # não há o que publicar, e não é questão de conteúdo.
  def self.arquivo(valor)
    entrega = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(valor)
    return descartar('entrega que não é texto nem arquivo') if entrega.nil?

    legenda = texto(entrega.legenda)
    reserva = texto(entrega.reserva)
    return descartar('entrega de arquivo sem legenda ou sem reserva') if legenda.nil? || reserva.nil?

    ::Autonomia::Agents::Tools::EntregaDeArquivo.new(url: entrega.url, nome: entrega.nome,
                                                     legenda: legenda, reserva: reserva).to_h
  end

  def self.descartar(motivo)
    Rails.logger.warn("[autonomia][tool] entrega descartada: #{motivo}")
    nil
  end

  private

  # Limita a quantidade e põe cada entrega na forma em que ela sai.
  def sanitize(list)
    Array(list).filter_map { |entrega| self.class.entregavel(entrega) }.first(MAX_DELIVERIES)
  end

  # Código curto e previsível (o mesmo cuidado de `Bound#http_error_code`): nunca deixa texto livre
  # de exceção virar identificador que depois vai parar em log ou métrica.
  def sanitize_code(code)
    value = code.to_s.strip.downcase.tr(' ', '_')
    return if value.blank?

    value.match?(/\A[a-z0-9_]{1,60}\z/) ? value : 'tool_failed'
  end
end
