# A ENTREGA EM PEDAÇOS ESTÁ NO MEIO (#2154, revisão). A IA de Atribuição que avalia depois da fala do agente
# (Crm::Ai::AvaliacaoDepoisDaFala) não entrega a conversa enquanto o agente ainda está "digitando" a resposta do turno
# seguinte: entregar ali cortaria a fala no meio (o pedaço seguinte vê a pessoa no nome e para). Ela espera e tenta de
# novo.
#
# Os sinais que já existiam não dizem isso: a marca do debounce do ReplyJob (`pending_message_id`) não é limpa depois da
# resposta, a posse do turno (PosseDoTurno) dura um dia de propósito, e o token de cada pedaço só existe depois que ele
# sai (ninguém sabe, olhando a conversa, quantos ainda faltam). Por isso uma chave curta no Redis, por conversa:
# gravada quando a cadeia é agendada (Operate::Responder) e renovada a cada pedaço agendado (ChunkedDeliveryJob), e
# solta quando a cadeia termina, por qualquer motivo. O valor é o turno e o vínculo: a cadeia velha que para não apaga a
# marca de uma cadeia nova (compare-and-delete). O TTL cobre a maior pausa entre dois pedaços (30 s) com folga; um
# job que caiu no meio não prende a conversa por mais que isso.
#
# Nunca levanta: é um sinal de cortesia sobre a entrega, que segue sem ele.
module Autonomia::Agents::Operate::CadeiaEmCurso
  CHAVE = 'autonomia:cadeia_em_curso:%<conversa>d'.freeze
  TTL = 2.minutes

  module_function

  def marcar(conversation_id, reply_to_message_id, agent_inbox_id)
    ::Redis::Alfred.set(chave(conversation_id), valor(reply_to_message_id, agent_inbox_id), ex: TTL.to_i)
  rescue StandardError
    nil
  end

  def soltar(conversation_id, reply_to_message_id, agent_inbox_id)
    ::Redis::Alfred.delete_if_equals(chave(conversation_id), valor(reply_to_message_id, agent_inbox_id))
  rescue StandardError
    nil
  end

  def em_curso?(conversation_id)
    ::Redis::Alfred.exists?(chave(conversation_id))
  rescue StandardError
    false
  end

  def chave(conversation_id) = format(CHAVE, conversa: conversation_id)

  def valor(reply_to_message_id, agent_inbox_id) = "#{reply_to_message_id}:#{agent_inbox_id}"
end
