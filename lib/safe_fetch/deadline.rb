# O PRAZO DE UMA TRANSFERÊNCIA (`total_timeout:`), monotônico: o prazo do CORPO com teto por leitura,
# e o teto por operação da conexão e da espera pelos cabeçalhos.
#
# `open_timeout` e `read_timeout` do Net::HTTP valem por OPERAÇÃO: um servidor que entrega um byte por
# segundo nunca estoura o `read_timeout` e segura quem baixa pelo tempo que quiser. Com o prazo, cada
# leitura do corpo passa a esperar no máximo o que resta dele. O Net::HTTP guarda o `read_timeout` no
# `Net::BufferedIO` da conexão e o consulta a cada espera (`rbuf_fill`); apertar o `read_timeout`
# DESSE socket entre um pedaço e o próximo é o que faz a espera seguinte caber no prazo. Sem prazo
# (`total_timeout` nil) nada muda.
#
# O QUE O PRAZO NÃO COBRE (ressalva registrada na rodada 7 da entrega 11; a decisão foi NÃO implementar
# um orçamento cancelável — uma thread vigia fechando o socket é risco maior que o benefício): a
# resolução de DNS, que o ssrf_filter faz antes de conectar, no resolvedor do sistema (`Resolv`), com
# os tempos dele; a espera pelos cabeçalhos, que é limitada pelo prazo só como teto POR OPERAÇÃO
# (`RequestOptions#bounded_by_total`) — cabeçalhos que gotejam abaixo dele evadem; e as linhas de
# controle do chunked entre dois pedaços, cada uma uma leitura com o teto do saldo. O nome da opção
# (`total_timeout`) é o da API e ficou; o que ela cobre é isto.
class SafeFetch::Deadline
  def initialize(total_timeout)
    @total_timeout = total_timeout
    @started_at = now
    @binding = false
    @sem_socket_registrado = false
  end

  # Segundos que restam (negativo quando venceu); nil sem prazo.
  def remaining
    return if @total_timeout.nil?

    @total_timeout - (now - @started_at)
  end

  # O prazo é o que limita a PRÓXIMA espera do socket? Verdadeiro depois de `enforce!` ter apertado o
  # `read_timeout` abaixo do que ele tinha: um `Net::ReadTimeout` que vier em seguida é o prazo
  # vencendo, não uma leitura isolada que travou.
  def binding?
    @binding
  end

  def exceeded_message
    "exceeded total_timeout of #{@total_timeout} seconds"
  end

  # Levanta `TotalTimeoutError` se o prazo venceu; senão aperta o `read_timeout` de `socket` para o que
  # resta. Só toca no socket que expõe `read_timeout=` (o `Net::BufferedIO`).
  def enforce!(socket)
    left = remaining
    return if left.nil?
    raise SafeFetch::TotalTimeoutError, exceeded_message if left <= 0

    tighten!(socket, left)
  end

  private

  # SEM SOCKET NÃO HÁ TETO POR LEITURA, e o prazo vale só entre pedaços: é assim sob WebMock (a resposta
  # não tem socket) e seria assim se um Net::HTTP futuro deixasse de expor o ivar `@socket` da
  # resposta (o `Fetcher` o lê por `instance_variable_get`). Degradação REGISTRADA, uma vez por
  # transferência, com código fechado — nunca em silêncio (Codex, rodada 7 da entrega 11).
  def tighten!(socket, left)
    return registrar_sem_socket unless socket.respond_to?(:read_timeout=)

    current = socket.read_timeout
    return unless current.nil? || left < current

    socket.read_timeout = left
    @binding = true
  end

  def registrar_sem_socket
    return if @sem_socket_registrado

    @sem_socket_registrado = true
    Rails.logger.warn('[safe_fetch] total_timeout degradado motivo=sem_socket: sem teto por leitura, o prazo vale so entre pedacos')
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
