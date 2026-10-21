# F3 do tema 8 (#1429): o limite do antes e depois, como o do autoteste: no máximo 1 comparação a cada 2 minutos por
# agente e 10 por dia por conta. Cada comparação são 6 respostas do agente (3 perguntas, com cada base), pagas como no
# Testar. Contado no Redis, atômico (SET NX e INCR): dois pedidos juntos não passam os dois.
#
# O DIA é o da conta: o fuso dos relatórios e do painel (Crm::Timezone::Resolver: `reporting_timezone`, sem ele o padrão
# do produto). A chave leva a data local e expira na meia-noite local (com folga), que é quando o aviso diz que libera.
# Trocar o fuso da conta no meio do dia pode abrir uma contagem nova (a data local muda): aceito, porque o custo extra fica
# limitado a mais 10 comparações naquele dia e a troca de fuso é rara.
module Autonomia::Agents::BaseDeSeguros::Limite
  ENTRE_PEDIDOS = 2.minutes
  POR_DIA = 10
  FOLGA = 1.minute
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
    Redis::Alfred.expire(chave, segundos_ate_virar_o_dia(agent.account)) if total == 1
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
    "#{PREFIXO}:conta:#{account.id}:#{agora_na_conta(account).to_date.iso8601}"
  end

  def agora_na_conta(account)
    Time.current.in_time_zone(Crm::Timezone::Resolver.new(account: account).zone_or_default)
  end

  # Até a meia-noite local, com uma folga para a chave nunca sumir antes do dia virar.
  def segundos_ate_virar_o_dia(account)
    agora = agora_na_conta(account)
    (agora.end_of_day - agora).ceil + FOLGA.to_i
  end
end
