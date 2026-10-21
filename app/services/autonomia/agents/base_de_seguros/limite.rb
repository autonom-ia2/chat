# F3 do tema 8 (#1429): o limite do antes e depois, como o do autoteste: no máximo 1 comparação a cada 2 minutos por
# agente e 10 por dia por conta. Cada comparação são 6 respostas do agente (3 perguntas, com cada base), pagas como no
# Testar. Contado no Redis, atômico (SET NX e INCR): dois pedidos juntos não passam os dois.
module Autonomia::Agents::BaseDeSeguros::Limite
  ENTRE_PEDIDOS = 2.minutes
  POR_DIA = 10
  PREFIXO = 'autonomia:base_de_seguros:comparar'.freeze

  # Passou do limite. `motivo`: espere (2 min no agente) | amanha (10 no dia na conta).
  class Excedido < StandardError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super("comparar_#{motivo}")
    end
  end

  module_function

  # Reserva a vez do agente e conta uma no dia da conta, ou levanta Excedido.
  def reservar!(agent)
    raise Excedido, 'espere' unless Redis::Alfred.set(chave_do_agente(agent), '1', nx: true, ex: ENTRE_PEDIDOS.to_i)

    chave = chave_da_conta(agent.account)
    total = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 2.days.to_i) if total == 1
    return if total <= POR_DIA

    liberar!(agent)
    raise Excedido, 'amanha'
  end

  # A comparação falhou (a IA não respondeu): a pessoa pode tentar de novo sem esperar os 2 minutos. O dia segue contado.
  def liberar!(agent)
    Redis::Alfred.delete(chave_do_agente(agent))
  end

  def chave_do_agente(agent)
    "#{PREFIXO}:agente:#{agent.id}"
  end

  def chave_da_conta(account)
    "#{PREFIXO}:conta:#{account.id}:#{Time.zone.today.iso8601}"
  end
end
