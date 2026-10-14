# MEMÓRIA DO TURNO da agenda da IA (#1307): o gate das duas ferramentas (`available_for?` -> `Agenda.pode_marcar?`)
# e a instrução "# Agenda" liam o estado da página três vezes por turno, cada vez com a consulta da página, a de
# elegibilidade e a de pausas. Dentro de `no_turno` (o `Answerer#answer`), cada ESTADO é calculado uma vez; fora
# dele, nada é guardado e cada leitura vai ao banco. A instrução, com a agenda ativa, ainda monta a lista de pessoas
# uma vez por turno (uma consulta de elegibilidade e uma de pausas). As ferramentas, ao RODAR, sempre leem de novo.
module Autonomia::Agents::Tools::Native::AgendaDoTurno
  CHAVE = :autonomia_agenda_estado_do_turno

  # Aninhado, reaproveita a memória de fora.
  def self.no_turno
    return yield unless ActiveSupport::IsolatedExecutionState[CHAVE].nil?

    ActiveSupport::IsolatedExecutionState[CHAVE] = {}
    begin
      yield
    ensure
      ActiveSupport::IsolatedExecutionState.delete(CHAVE)
    end
  end

  def self.lembrar(chave)
    memoria = ActiveSupport::IsolatedExecutionState[CHAVE]
    return yield if memoria.nil?
    return memoria[chave] if memoria.key?(chave)

    memoria[chave] = yield
  end
end
