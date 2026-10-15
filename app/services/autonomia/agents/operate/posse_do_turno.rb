# "Um turno, uma ordem" (#1606, ponto 2): quem já está respondendo este turno. Um turno (a última mensagem do cliente
# de uma rajada) é respondido no máximo uma vez por vínculo: a chave `autonomia:turno:<conversa>:<mensagem>:<vínculo>`
# é tomada com SET NX pelo settle do ReplyJob, antes do Responder, ou pelo ReenfileirarTurno, que repassa a posse ao
# settle que enfileira. Sem ela, o settle que esperava o assunto e o reenfileirado pela troca de dono chamariam o
# Responder duas vezes para o mesmo dono (duas chamadas de IA e, na entrega em pedaços, duas cadeias disputando).
#
# O valor da chave é o job_id do settle que a tomou. O Sidekiq devolve à fila o job em curso no deploy (e o retry
# repete o job), sempre com o mesmo job_id: o mesmo settle rodando de novo reconhece a própria posse e responde, em vez
# de perder o turno para si mesmo e deixar o cliente sem resposta. Outro settle (job_id diferente) segue barrado.
#
# A chave dura a vida do turno (TTL de um dia), não só a janela do debounce: a marca do debounce não é limpa depois da
# resposta, e o caminho :responder do ReenfileirarTurno não tem prazo dentro desse dia. Com uma chave curta, o pedaço 0
# atrasado do dono antigo (ChunkedDeliveryJob) chamaria o ReenfileirarTurno, que tomaria de novo a chave do dono novo e
# enfileiraria outro settle para ele: o dono novo responderia duas vezes. Passado o dia, o ReenfileirarTurno também não
# refaz mais o turno.
#
# O turno respondido NÃO solta a chave, de propósito: ela é o que impede responder de novo o mesmo turno (dedupe). Solta
# só quem não entregou: o turno que falhou (exceção, IA sem resultado, resposta vazia — Operate::Responder), que pode ser
# retomado pelo mesmo dono ou pelo seguinte.
#
# Quem perde o turno porque o dono mudou solta a SUA chave, e só se ela ainda tiver o valor que ele tomou
# (compare-and-delete): se o turno voltar para ele (A→B→A), ele pode responder; uma posse mais nova dele não é apagada.
# Laço não há: só uma troca de dono de verdade reenfileira, e cada reenfileiramento precisa tomar a chave do destino.
#
# Só com a Fase 2 ligada. Fora dela nada aqui é lido nem gravado: o turno segue como sempre foi.
module Autonomia::Agents::Operate::PosseDoTurno
  TTL = 1.day
  # Quem tomou a chave sem ser um settle (o ReenfileirarTurno, que repassa a posse pelo argumento `posse`).
  REPASSADA = 'repassada'.freeze

  module_function

  def chave(conversation_id, message_id, agent_inbox_id)
    "autonomia:turno:#{conversation_id}:#{message_id}:#{agent_inbox_id}"
  end

  # true quando pode responder. `job_id`: o do settle que pergunta. `posse`: o id do vínculo cuja chave quem enfileirou
  # já tomou.
  def assumir?(conversation:, agent_inbox:, message_id:, job_id:, posse: nil)
    return true unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)
    return true if posse.present? && posse.to_i == agent_inbox.id
    return true if tomar?(conversation.id, message_id, agent_inbox.id, dono: job_id)

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:turno_em_curso, conversation_id: conversation.id,
                                                                               msg: message_id, agent_inbox: agent_inbox.id)
    false
  end

  # true quando a chave ficou com `dono`, agora ou antes (o mesmo job rodando de novo).
  def tomar?(conversation_id, message_id, agent_inbox_id, dono: REPASSADA)
    chave = chave(conversation_id, message_id, agent_inbox_id)
    return true if ::Redis::Alfred.set(chave, dono, nx: true, ex: TTL.to_i)

    dono != REPASSADA && ::Redis::Alfred.get(chave) == dono.to_s
  end

  # O valor com que um settle ficou com o turno: o job_id dele, ou REPASSADA quando a posse veio do ReenfileirarTurno.
  def valor(job_id:, posse:, agent_inbox:)
    posse.present? && posse.to_i == agent_inbox.id ? REPASSADA : job_id
  end

  # Solta só se a chave ainda for de quem pede (`valor`); sem valor, não solta nada.
  def soltar(conversation_id, message_id, agent_inbox_id, valor)
    return if valor.blank?

    ::Redis::Alfred.delete_if_equals(chave(conversation_id, message_id, agent_inbox_id), valor.to_s)
  end
end
