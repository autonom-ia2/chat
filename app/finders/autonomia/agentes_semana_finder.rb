# #1181 (L1) — números da semana por agente, para a lista inteira em consultas fixas (sem N+1).
# #2000: a conta é a única da IA (Autonomia::ContaDaIa), a mesma da linha da IA em CRM › Números › Equipe:
# - answered: conversas com resposta do agente na semana;
# - handed: conversas que o agente passou para alguém da equipe na semana (por horário, a pedido do cliente ou porque não
#   soube);
# - resolved: conversas resolvidas na semana em que o agente respondeu, sem ninguém da equipe no meio.
# `conversas`: as que quem pede pode abrir (ContaDaIa.visiveis): o cartão conta o mesmo conjunto que a lista que ele abre.
class Autonomia::AgentesSemanaFinder
  RANGE = '7d'.freeze

  def initialize(account:, agent_ids:, conversas: nil)
    @agent_ids = agent_ids
    @conta = ::Autonomia::ContaDaIa.new(account: account, range: ::Autonomia::ContaDaIa.semana(account), conversas: conversas)
  end

  def range
    RANGE
  end

  def from
    @conta.range.begin
  end

  def to
    @conta.range.end
  end

  # [{ agent_id:, answered:, handed:, resolved: }] na ordem de agent_ids; agente sem conversas sai com zeros.
  def call
    @conta.por_agente(@agent_ids).map do |id, numeros|
      { agent_id: id, answered: numeros[:atendeu], handed: numeros[:passou], resolved: numeros[:resolveuSozinha] }
    end
  end
end
