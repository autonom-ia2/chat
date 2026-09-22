# O que UMA consulta a uma ferramenta assíncrona devolveu (#313).
#
# A ferramenta não conhece conversa nem mensagem: ela só diz "ainda estou", "acabei" ou "falhei", e
# entrega os ARQUIVOS que já servem ao cliente. Quem publica é o job.
#
# `deliveries` SÃO SÓ ARQUIVOS (`EntregaDeArquivo`, na forma serializada: a URL de onde o publicador baixa e o
# nome). Desde a PR C o motor não publica texto ao cliente: o que o cliente lê sobre a cotação é a Lia quem
# escreve, num turno de modelo acionado por um EVENTO (`Tools::Evento`). Um texto que chegue aqui é descartado,
# registrado, e não vai a lugar nenhum.
#
# `evento` é o desfecho que a própria consulta já conhece — a recusa do envio (`falta_dado`, `ramo_desconhecido`,
# `falhou`) — e viaja até `Tools::Encerramento#concluir`, que o dispara. Tipo fora da lista fechada vira nil.
#
# A ferramenta NUNCA tem canal para mandar erro ao cliente: falha se declara em `failure_code` (um
# código curto nosso). Isso preserva a fronteira que o `Bound` já defende hoje — mensagem de exceção pode
# carregar requisição assinada ou texto vindo do portal (`Insurance::Connector::Error#business_message`
# traz até 160 chars do AGGER), e nada disso pode chegar ao WhatsApp de um cliente.
class Autonomia::Agents::Tools::Progress
  MAX_DELIVERIES = 5

  attr_reader :status, :handle, :deliveries, :failure_code, :evento

  # `confirmar_logo`: a ferramenta pede a consulta seguinte no primeiro intervalo da progressão, e não no
  # da tentativa (`AsyncRunJob#reschedule`). A cotação pede quando a próxima leitura pode fechá-la.
  def self.running(deliveries: [], handle: nil, confirmar_logo: false)
    new(status: :running, deliveries: deliveries, handle: handle, confirmar_logo: confirmar_logo)
  end

  def self.done(deliveries: [], handle: nil, evento: nil)
    new(status: :done, deliveries: deliveries, handle: handle, evento: evento)
  end

  def self.failed(code, deliveries: [])
    new(status: :failed, deliveries: deliveries, failure_code: code)
  end

  # `desfecho`: `failure_code:` (na falha), `confirmar_logo:` (no `running`) e `evento:` (no `done`) — cada status usa
  # um, e os construtores de classe acima são o jeito de montar.
  def initialize(status:, deliveries: [], handle: nil, **desfecho)
    @status = status.to_sym
    @handle = handle
    @failure_code = sanitize_code(desfecho[:failure_code])
    @deliveries = sanitize(deliveries)
    @confirmar_logo = desfecho[:confirmar_logo] == true
    @evento = sanitize_evento(desfecho[:evento])
  end

  def running?
    status == :running
  end

  # -> a ferramenta pediu a consulta seguinte no primeiro intervalo? Só vale para `running`.
  def confirmar_logo?
    running? && @confirmar_logo
  end

  def done?
    status == :done
  end

  def failed?
    status == :failed
  end

  # UMA ENTREGA, NA FORMA EM QUE ELA VAI SAIR — a entrega de arquivo serializada, ou nil quando não é arquivo.
  #
  # PÚBLICA PORQUE A FERRAMENTA PRECISA DA MESMA RESPOSTA ANTES DE GRAVAR: a identidade de uma entrega é calculada
  # sobre a forma final (`EntregaPublicada.token_de`), e a ferramenta a calcula antes de avançar o handle.
  def self.entregavel(valor)
    entrega = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(valor)
    return descartar(valor.is_a?(String) ? 'texto: o motor só publica arquivo' : 'entrega que não é arquivo') if entrega.nil?

    entrega.to_h
  end

  # Só a CLASSE do motivo vai ao log: o conteúdo de uma entrega que não é arquivo pode ser qualquer coisa.
  def self.descartar(motivo)
    Rails.logger.warn("[autonomia][tool] entrega descartada: #{motivo}")
    nil
  end
  private_class_method :descartar

  private

  # Limita a quantidade e põe cada entrega na forma em que ela sai.
  def sanitize(list)
    Array(list).filter_map { |entrega| self.class.entregavel(entrega) }.first(MAX_DELIVERIES)
  end

  def sanitize_evento(evento)
    return nil if evento.blank?
    return evento.to_s if ::Autonomia::Agents::Tools::Evento::TIPOS.include?(evento.to_s)

    Rails.logger.warn('[autonomia][tool] evento descartado: fora da lista fechada')
    nil
  end

  # Código curto e previsível (o mesmo cuidado de `Bound#http_error_code`): nunca deixa texto livre
  # de exceção virar identificador que depois vai parar em log ou métrica.
  def sanitize_code(code)
    value = code.to_s.strip.downcase.tr(' ', '_')
    return if value.blank?

    value.match?(/\A[a-z0-9_]{1,60}\z/) ? value : 'tool_failed'
  end
end
