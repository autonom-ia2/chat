# "Um turno, uma ordem" (#1606, ponto 2): quem já está respondendo este turno. Um turno (a última mensagem do cliente
# de uma rajada) é respondido no máximo uma vez por vínculo: a chave `autonomia:turno:<conversa>:<mensagem>:<vínculo>`
# é tomada com SET NX pelo settle do ReplyJob, antes do Responder, ou pelo ReenfileirarTurno, que repassa a posse ao
# settle que enfileira. Sem ela, o settle que esperava o assunto e o reenfileirado pela troca de dono chamariam o
# Responder duas vezes para o mesmo dono (duas chamadas de IA e, na entrega em pedaços, duas cadeias disputando).
#
# Quem perde o turno porque o dono mudou solta a chave: se o turno voltar para ele (A→B→A), ele pode responder.
# Laço não há: só uma troca de dono de verdade reenfileira, e o turno vence com a janela do debounce mais a folga.
#
# Só com a Fase 2 ligada. Fora dela nada aqui é lido nem gravado: o turno segue como sempre foi.
module Autonomia::Agents::Operate::PosseDoTurno
  TTL = 2.minutes

  module_function

  def chave(conversation_id, message_id, agent_inbox_id)
    "autonomia:turno:#{conversation_id}:#{message_id}:#{agent_inbox_id}"
  end

  # true quando pode responder. `posse` é o id do vínculo cuja chave quem enfileirou já tomou.
  def assumir?(conversation:, agent_inbox:, message_id:, posse: nil)
    return true unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)
    return true if posse.present? && posse.to_i == agent_inbox.id
    return true if tomar?(conversation.id, message_id, agent_inbox.id)

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:turno_em_curso, conversation_id: conversation.id,
                                                                               msg: message_id, agent_inbox: agent_inbox.id)
    false
  end

  def tomar?(conversation_id, message_id, agent_inbox_id)
    ::Redis::Alfred.set(chave(conversation_id, message_id, agent_inbox_id), 1, nx: true, ex: TTL.to_i) ? true : false
  end

  def soltar(conversation_id, message_id, agent_inbox_id)
    ::Redis::Alfred.delete(chave(conversation_id, message_id, agent_inbox_id))
  end
end
