# O PRAZO TOTAL de uma transferência (`total_timeout:`), monotônico.
#
# `open_timeout` e `read_timeout` do Net::HTTP valem por OPERAÇÃO: um servidor que entrega um byte por
# segundo nunca estoura o `read_timeout` e segura quem baixa pelo tempo que quiser. O prazo total é o
# teto da transferência inteira — conexão, cabeçalhos e corpo —, e cada leitura do corpo passa a
# esperar no máximo o que resta dele. O Net::HTTP guarda o `read_timeout` no `Net::BufferedIO` da
# conexão e o consulta a cada espera (`rbuf_fill`); apertar o `read_timeout` DESSE socket entre um
# pedaço e o próximo é o que faz a espera seguinte caber no prazo. Sem prazo (`total_timeout` nil)
# nada muda.
#
# O que o prazo NÃO cobre: a resolução de DNS, que o ssrf_filter faz antes de conectar, no
# resolvedor do sistema (`Resolv`), com os tempos dele.
class SafeFetch::Deadline
  def initialize(total_timeout)
    @total_timeout = total_timeout
    @started_at = now
    @binding = false
  end

  # Segundos que restam (negativo quando venceu); nil sem prazo.
  def remaining
    return if @total_timeout.nil?

    @total_timeout - (now - @started_at)
  end

  # O prazo é o que limita a PRÓXIMA espera do socket? Verdadeiro depois de `enforce!` ter apertado o
  # `read_timeout` abaixo do que ele tinha: um `Net::ReadTimeout` que vier em seguida é o prazo total
  # vencendo, não uma leitura isolada que travou.
  def binding?
    @binding
  end

  def exceeded_message
    "exceeded total_timeout of #{@total_timeout} seconds"
  end

  # Levanta `TotalTimeoutError` se o prazo venceu; senão aperta o `read_timeout` de `socket` para o que
  # resta. Só toca no socket que expõe `read_timeout=` (o `Net::BufferedIO`); sob WebMock a resposta não
  # tem socket, e o prazo vale só entre pedaços.
  def enforce!(socket)
    left = remaining
    return if left.nil?
    raise SafeFetch::TotalTimeoutError, exceeded_message if left <= 0

    tighten!(socket, left)
  end

  private

  def tighten!(socket, left)
    return unless socket.respond_to?(:read_timeout=)

    current = socket.read_timeout
    return unless current.nil? || left < current

    socket.read_timeout = left
    @binding = true
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
