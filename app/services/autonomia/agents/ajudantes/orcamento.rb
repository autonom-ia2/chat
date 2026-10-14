# Tema 14 (#1434) — os dois tetos simples de UMA resposta do principal: quantas consultas aos ajudantes e quanto tempo
# desde o começo da resposta. Vive no `Answerer` do principal; nada desce para o ajudante (profundidade 1).
class Autonomia::Agents::Ajudantes::Orcamento
  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def initialize(consultas: ::Autonomia::Agents::Ajudantes::CONSULTAS_POR_RESPOSTA,
                 prazo: ::Autonomia::Agents::Ajudantes::PRAZO_DA_RESPOSTA)
    @teto_de_consultas = consultas
    @prazo = prazo
    @inicio = self.class.agora
    @consultas = 0
  end

  # -> 'consultas' | 'prazo' quando a próxima consulta não pode rodar; nil quando pode, e aí ela já é contada.
  def reservar
    return 'consultas' if @consultas >= @teto_de_consultas
    return 'prazo' if self.class.agora - @inicio > @prazo

    @consultas += 1
    nil
  end
end
