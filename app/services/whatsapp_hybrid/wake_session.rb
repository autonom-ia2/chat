# Religa uma sessão parada no motor antes de tirar o aparelho do celular (#1487). Logout numa sessão parada (WhatsApp
# API pausado) pode não desvincular o aparelho: a sessão precisa estar no ar. O TeardownSessionJob usa o mesmo pedido e
# espera de forma assíncrona (retry); o reconectar da aba espera aqui, curto, porque a pessoa está olhando a tela.
class WhatsappHybrid::WakeSession
  WAIT_TRIES = 5
  WAIT_SECONDS = 1
  WAKING = %w[STOPPED STARTING].freeze

  # Reconectar uma conexão pausada: a sessão parada sobe antes do logout, para o aparelho sair do celular de verdade,
  # e a pausa sai. Sem pausa, nada a fazer.
  def self.unpause!(client, connection)
    return unless connection.paused?

    new(client, connection.session_name).call
    connection.update!(paused_at: nil)
  end

  def initialize(client, session_name)
    @client = client
    @session_name = session_name
  end

  # Dá start se a sessão está parada. Devolve o estado lido antes do pedido (nil: o motor não tem a sessão).
  def start_if_stopped!
    status = @client.get_session(@session_name)&.dig('status')
    @client.start_session(@session_name) if status == 'STOPPED'
    status
  rescue Waha::Client::NotFound
    nil
  end

  # Religa e espera a sessão sair de "parada/subindo", no máximo WAIT_TRIES vezes. Não subiu a tempo: segue assim mesmo.
  def call
    return unless start_if_stopped! == 'STOPPED'

    WAIT_TRIES.times do
      Kernel.sleep(WAIT_SECONDS)
      break unless WAKING.include?(@client.get_session(@session_name)&.dig('status'))
    end
  end
end
