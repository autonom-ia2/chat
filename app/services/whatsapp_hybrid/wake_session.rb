# Religa uma sessão parada no motor antes de tirar o aparelho do celular (#1487). Logout numa sessão parada (WhatsApp
# API pausado) pode não desvincular o aparelho: a sessão precisa estar no ar. O TeardownSessionJob usa o mesmo pedido e
# espera de forma assíncrona (retry, sem pressa); o reconectar da aba espera aqui, com teto curto (~6 s), porque a pessoa
# está olhando a tela. Não subiu a tempo: o reconectar recusa sem logout ("está religando, tente de novo") e, na
# tentativa seguinte, a sessão já está de pé.
class WhatsappHybrid::WakeSession
  # A sessão foi religada mas ainda não está de pé: o painel pede para tentar de novo em alguns segundos.
  class NotReady < StandardError; end

  WAKING = %w[STOPPED STARTING].freeze
  READY = %w[WORKING SCAN_QR_CODE].freeze
  DEADLINE_SECONDS = 6
  STEP_TIMEOUT = 3
  WAIT_SECONDS = 1
  # Limite de voltas além do relógio (e o que encerra o laço nos testes, com o sleep simulado).
  MAX_TRIES = 6

  # Reconectar uma conexão pausada: a sessão parada sobe antes do logout e a pausa sai. Sem pausa, nada a fazer.
  # Não subiu a tempo: a pausa fica e o erro sobe, sem logout.
  def self.unpause!(client, connection)
    return unless connection.paused?
    raise NotReady unless new(client, connection.session_name).call

    connection.update!(paused_at: nil)
  end

  def initialize(client, session_name)
    @client = client
    @session_name = session_name
  end

  # Dá start se a sessão está parada. Devolve o estado lido antes do pedido (nil: o motor não tem a sessão).
  # timeout: só o reconectar passa um curto; o teardown usa o padrão do cliente.
  def start_if_stopped!(timeout: nil)
    status = @client.get_session(@session_name, **timeout_option(timeout))&.dig('status')
    @client.start_session(@session_name, **timeout_option(timeout)) if status == 'STOPPED'
    status
  rescue Waha::Client::NotFound
    nil
  end

  # Verdadeiro quando dá para seguir: a sessão está de pé (conectada ou pedindo QR) ou o motor não a tem mais (o
  # reconectar recria). Falso quando ela não subiu dentro do teto.
  # Motor sem resposta no start (timeout) também é "ainda subindo": o painel pede para tentar de novo.
  def call
    started_at = monotonic_now
    status = start_if_stopped!(timeout: STEP_TIMEOUT)
    return true unless WAKING.include?(status)

    wait_until_up(started_at)
  rescue Waha::Client::Timeout
    gave_up!
  end

  private

  # O prazo é recalculado depois de cada espera: a consulta nunca passa do que falta para o teto.
  def wait_until_up(started_at)
    MAX_TRIES.times do
      break if remaining(started_at) <= 0

      Kernel.sleep(WAIT_SECONDS)
      left = remaining(started_at)
      break if left <= 0
      return true if READY.include?(current_status([STEP_TIMEOUT, left.ceil].min))
    end
    gave_up!
  rescue Waha::Client::NotFound
    true
  end

  def remaining(started_at)
    DEADLINE_SECONDS - (monotonic_now - started_at)
  end

  def gave_up!
    Rails.logger.warn("[whatsapp_hybrid] wake session=#{@session_name}: não subiu em #{DEADLINE_SECONDS}s")
    false
  end

  # Sem resposta (timeout) conta como "ainda subindo"; 404 sobe para quem chamou.
  def current_status(timeout)
    @client.get_session(@session_name, timeout: timeout)&.dig('status')
  rescue Waha::Client::NotFound
    raise
  rescue Waha::Client::Error
    nil
  end

  def timeout_option(timeout)
    timeout ? { timeout: timeout } : {}
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
