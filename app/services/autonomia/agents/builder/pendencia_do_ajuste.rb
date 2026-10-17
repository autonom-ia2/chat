# #1428 (tema 6, parte 2) — a pendência do turno de AJUSTE no piloto. Incluído no Builder junto com os outros módulos
# do ajuste; fora do piloto nada daqui roda.
#
# PENDÊNCIA: a pergunta aberta (`pergunta_pendente`) só sai quando o MODELO diz que a fala a resolveu
# (`pendencia_resolvida`), ou quando o código abre uma pergunta nova sobre o turno. Os turnos em laço (o modelo aplicou ou
# perguntou de novo sem resolvê-la, qualquer que seja o texto) contam; a pergunta do dono e os textos fixos não. No teto,
# a pendência não some calada: fica como contexto, sem a ordem de repetir (`pendencia_no_teto`).
module Autonomia::Agents::Builder::PendenciaDoAjuste
  TETO_DE_TURNOS_DA_PENDENCIA = 3

  # A descrição do campo do schema do ajuste que o modelo preenche sobre a pendência (AjustePorLista::SCHEMA).
  PENDENCIA_RESOLVIDA_DESCRIPTION =
    'So vale quando o contexto interno traz uma PERGUNTA PENDENTE sua. true quando a ultima fala do dono responde ' \
    'essa pergunta, ou quando ela nao vale mais porque o dono mudou de assunto de vez ou a desfez. false quando ela ' \
    'continua sem resposta (o dono pediu outra coisa sem responder) ou quando nao ha pergunta pendente. Se voce ' \
    'repetir a pergunta em next_question, deixe false.'.freeze

  private

  # A pendência de antes do turno, a menos que o MODELO diga que a fala a resolveu. O código nunca a apaga sozinho.
  def pendencia_mantida(parsed)
    resolvida?(parsed) ? '' : @pendencia_anterior.to_s
  end

  def resolvida?(parsed)
    parsed.to_h['pendencia_resolvida'] == true
  end

  # -> as chaves da pendência no state. `origem`: :modelo (pergunta dele), :mantida (a anterior) ou :codigo (pergunta
  # nova que o código abre sobre o turno, zera). `laco`: o turno conta para o teto (o modelo aplicou ou perguntou de
  # novo sem resolver a pendência).
  def pendencia_no_estado(pendencia, parsed, origem:, laco:)
    pendencia = pendencia.to_s
    nova = pendencia.blank? || @pendencia_anterior.blank? || origem == :codigo || resolvida?(parsed)
    return { 'pergunta_pendente' => pendencia, 'pendencia_turnos' => 0, 'pendencia_no_teto' => false } if nova

    turnos = laco ? @turnos_da_pendencia + 1 : @turnos_da_pendencia
    { 'pergunta_pendente' => pendencia, 'pendencia_turnos' => turnos,
      'pendencia_no_teto' => turnos >= TETO_DE_TURNOS_DA_PENDENCIA }
  end

  # No teto, a pendência segue como contexto, sem a ordem de repetir.
  def pendencia_no_teto_context(pergunta)
    'CONTEXTO INTERNO (não é fala do usuário). PERGUNTA QUE FICOU SEM RESPOSTA (já repetida o bastante; NÃO a ' \
      "repita e não a cobre): \"#{pergunta}\". Use só como contexto. Se a fala do dono a responder, aplique e marque " \
      'pendencia_resolvida=true.'
  end
end
