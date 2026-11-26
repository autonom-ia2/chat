# O TURNO AINDA É ESTE? As duas perguntas que o `ChunkedDeliveryJob` faz antes de cada pedaço sobre a vez do turno, juntas.
module Autonomia::Agents::Operate::ChunkedDeliveryJob::TurnoDoPedaco
  private

  # Mesmo token-guard do ReplyJob: o último incoming da janela de debounce ainda é o nosso?
  # Sem stamp (conversa sem debounce, ex.: caminho de teste) -> considera válido (não aborta).
  # #3225: a mensagem mais nova que o turno leu no meio (as lidas do meta), ainda sem resposta própria, não o supera
  # (o mesmo critério do ReplyJob.turno_superado?). Sem lidas, o de sempre.
  def current_turn?(conversation, reply_to_message_id, meta = {})
    stamp = conversation.reload.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
    pending = stamp.is_a?(Hash) ? stamp['pending_message_id'] : nil
    pending.blank? || pending == reply_to_message_id ||
      ::Autonomia::Agents::Operate::LeituraNoTurno.cobre?(conversation, pending, Array(meta.to_h['lidas_no_turno']))
  end

  # #3225: no 1º pedaço, com a flag, uma resposta deste agente já leu esta mensagem no meio do turno dela e saiu.
  def respondida_junto?(conversation, agent_inbox, reply_to_message_id, index)
    index.zero? && ::Autonomia::Agents::Operate::LeituraNoTurno.respondida_junto?(conversation, reply_to_message_id, agent_inbox.agent)
  end
end
