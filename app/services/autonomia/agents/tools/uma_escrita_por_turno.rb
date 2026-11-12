# A FERRAMENTA QUE ESCREVE RODA UMA VEZ POR TURNO (#2918, revisão de segurança). O Rodrigo autorizou o agente com pronta
# a CONSULTAR até 3 vezes por resposta, não a escrever. Sem esta trava, um texto injetado pelo cliente podia fazer a
# ferramenta que escreve (`Bound#escreve?`: a HTTP fora do GET, cada vez com outra `Idempotency-Key`; a nativa que
# declara `escreve?`, como marcar horário) rodar até 3 vezes no turno. Com ela, a segunda chamada da mesma ferramenta no
# turno (na mesma rodada ou em outra) não vai ao sistema de fora: o modelo lê `JA_FEITA` e a recusa fica registrada. A
# leitura (GET, as prontas, a nativa que só lê) segue livre, e quem chama decide quando a trava vale (`Answerer`,
# `uma_escrita_por_turno`): só nas rodadas das prontas. O ajudante e a Lia seguem como antes.
class Autonomia::Agents::Tools::UmaEscritaPorTurno
  JA_FEITA = 'Esta ação já foi feita neste turno; não repita. Responda ao cliente com o resultado que você já recebeu.'.freeze

  def initialize(agente:, delivery:)
    @agente = agente
    @delivery = delivery
    @feitas = Set.new
  end

  # -> { chamada => saída para o modelo } das que não rodam: da segunda em diante de uma mesma ferramenta que escreve. A
  # chamada a um especialista ou ajudante (que tem a precedência no despacho) fica fora.
  def repetidas(calls, tools_by_slug, specialists_by_function)
    Array(calls).each_with_object({}.compare_by_identity) do |call, repetidas|
      nome = call['name'].to_s
      next if specialists_by_function.key?(nome) || !tools_by_slug[nome]&.escreve?
      next if @feitas.add?(nome)

      repetidas[call] = recusa_registrada(nome)
    end
  end

  private

  def recusa_registrada(slug)
    ::Autonomia::Agents::Tools::Recusa.registrar('acao_ja_feita_neste_turno', slug: slug, agente: @agente,
                                                                              conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(@delivery))
    JA_FEITA
  end
end
