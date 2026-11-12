# AS RODADAS DE FERRAMENTA DO TURNO (#2918): uma função só para o atendimento (`Operate::Responder`), o Testar
# (`Playground`) e o Copiloto (`Copilot`). Régua do Rodrigo: o que o dono testa é o que o cliente recebe.
#
# A ordem: as do principal com ajudante (tema 14, #1434: 6); as do agente com pronta no turno (as do Experimente, 3,
# `FerramentasProntas.rodadas`); e a regra de sempre (`QuoteAgent::Builder.rodadas_do_turno`: 6 na Lia, 1 nos demais).
# A Lia nunca tem ajudante nem pronta no turno (as duas devolvem nil para ela), então a regra dela vale inteira.
module Autonomia::Agents::RodadasDoTurno
  module_function

  # -> kwargs para o `Answerer` (`max_rodadas`, `max_segundos`).
  def para(agent)
    ::Autonomia::Agents::Ajudantes.rodadas(agent) || ::Autonomia::FerramentasProntas.rodadas(agent) ||
      ::Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(agent)
  end
end
