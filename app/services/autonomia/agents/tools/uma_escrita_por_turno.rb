# A FERRAMENTA QUE ESCREVE RODA UMA VEZ POR TURNO (#2918, revisão de segurança). O Rodrigo autorizou o agente com pronta
# a CONSULTAR até 3 vezes por resposta, não a escrever. Sem esta trava, um texto injetado pelo cliente podia fazer a
# ferramenta que escreve (`Bound#escreve?`: a HTTP fora do GET, cada vez com outra `Idempotency-Key`; a nativa que
# declara `escreve?`, como marcar horário) rodar até 3 vezes no turno.
#
# - Numa rodada, só a primeira chamada de cada ferramenta que escreve roda; as outras não vão ao sistema de fora.
# - A ferramenta só conta como FEITA quando rodou sem recusa registrada (`concluir`). A escrita que falhou (a
#   conferência recusou, o horário era inválido, o sistema devolveu 4xx ou 5xx, a consulta não disparou: todas passam
#   pelo registro de recusa) não trava: o modelo corrige o dado e tenta de novo, e o agente não confirma ao cliente o
#   que não aconteceu. O 2xx do sistema de fora é feito, mesmo com `{"error"}` no corpo: a chave de idempotência já
#   avançou com ele (`ChaveDeIdempotencia.concluir`), e outra tentativa podia duplicar a escrita.
# - A chamada travada não roda: o modelo lê `NAO_FEITA` (o pedido não foi feito, e pode ter outros argumentos), e a
#   recusa fica registrada.
#
# A leitura (GET, as prontas, a nativa que só lê) segue livre, e quem chama decide quando a trava vale (`Answerer`,
# `uma_escrita_por_turno`): só nas rodadas das prontas. O ajudante e a Lia seguem como antes.
class Autonomia::Agents::Tools::UmaEscritaPorTurno
  NAO_FEITA = 'Esta ferramenta só roda uma vez por resposta; este pedido NÃO foi feito. Diga ao cliente que faz na ' \
              'próxima mensagem.'.freeze

  def initialize(agente:, delivery:)
    @agente = agente
    @delivery = delivery
    @feitas = Set.new
  end

  # -> { chamada => saída para o modelo } das que não rodam: a ferramenta que escreve já feita neste turno, ou a segunda
  # chamada dela nesta rodada. A chamada a um especialista ou ajudante (a precedência do despacho) fica fora.
  def repetidas(calls, tools_by_slug, specialists_by_function)
    nesta_rodada = Set.new
    Array(calls).each_with_object({}.compare_by_identity) do |call, repetidas|
      nome = call['name'].to_s
      next unless escrita?(nome, tools_by_slug, specialists_by_function)
      next if @feitas.exclude?(nome) && nesta_rodada.add?(nome)

      repetidas[call] = recusa_registrada(nome)
    end
  end

  # A chamada rodou: a escrita conta como feita só sem recusa registrada (a nossa, ou o 4xx/5xx do sistema de fora).
  def concluir(call, tools_by_slug, specialists_by_function, recusou:)
    nome = call['name'].to_s
    return if recusou || !escrita?(nome, tools_by_slug, specialists_by_function)

    @feitas << nome
  end

  private

  def escrita?(nome, tools_by_slug, specialists_by_function)
    !specialists_by_function.key?(nome) && tools_by_slug[nome]&.escreve? == true
  end

  def recusa_registrada(slug)
    ::Autonomia::Agents::Tools::Recusa.registrar('acao_ja_feita_neste_turno', slug: slug, agente: @agente,
                                                                              conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(@delivery))
    NAO_FEITA
  end
end
