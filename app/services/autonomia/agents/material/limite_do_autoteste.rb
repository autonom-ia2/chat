# #1426 (tema 4b, revisão adversarial) — o limite de rodadas do autoteste, por agente, decidido e contado sob a MESMA
# trava da linha que abre a rodada (Autoteste.pedir!), então dois pedidos juntos não passam os dois:
# - pedido da pessoa ("Testar de novo"): no máximo um a cada 2 min e 10 rodadas por dia;
# - rodada automática (a base mudou): só conta no teto do dia quando a conta usa a chave de IA da PLATAFORMA. Sem o
#   app `crm_kanban_ai` na conta, o CredentialResolver devolve a chave da instalação (`system`): quem paga é a
#   Autonom.ia, e aí toda rodada conta. Com a chave da própria conta (`hook`), a automática já tem o limite de 1 a cada
#   30 min (Autoteste.quando_automatica).
# Guarda em config['autoteste']: dia (data de hoje), rodadas_no_dia, ultimo_pedido.
module Autonomia::Agents::Material::LimiteDoAutoteste
  ENTRE_PEDIDOS = 2.minutes
  POR_DIA = 10

  # O pedido da pessoa passou do limite. `motivo`: espere (2 min) | amanha (10 no dia).
  class Excedido < StandardError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super("autoteste_#{motivo}")
    end
  end

  module_function

  def da_plataforma?(agent)
    Crm::Ai::CredentialResolver.new(account: agent.account).resolve&.dig(:source) == :system
  end

  # nil quando pode abrir a rodada; senão o motivo.
  def bloqueio(atual, quando, plataforma)
    if quando == 'pedido'
      return 'espere' if pedido_recente?(atual)
      return 'amanha' if rodadas_de_hoje(atual) >= POR_DIA
    elsif plataforma && rodadas_de_hoje(atual) >= POR_DIA
      return 'amanha'
    end
    nil
  end

  # A rodada nova (`base`) com a contagem de hoje atualizada.
  def contar(base, atual, quando, plataforma)
    conta = quando == 'pedido' || plataforma
    contagem = { 'dia' => hoje, 'rodadas_no_dia' => rodadas_de_hoje(atual) + (conta ? 1 : 0) }
    ultimo = quando == 'pedido' ? Time.current.iso8601 : atual.to_h['ultimo_pedido']
    base.merge(contagem).merge('ultimo_pedido' => ultimo)
  end

  def rodadas_de_hoje(atual)
    atual.to_h['dia'] == hoje ? atual.to_h['rodadas_no_dia'].to_i : 0
  end

  def pedido_recente?(atual)
    ultimo = Time.zone.parse(atual.to_h['ultimo_pedido'].to_s)
    ultimo.present? && ultimo.after?(ENTRE_PEDIDOS.ago)
  end

  def hoje
    Time.zone.today.iso8601
  end
end
