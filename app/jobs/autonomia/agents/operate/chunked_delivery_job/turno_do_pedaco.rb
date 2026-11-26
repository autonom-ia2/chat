# O TURNO AINDA É ESTE? As perguntas que o `ChunkedDeliveryJob` faz antes de cada pedaço sobre a vez do turno, juntas.
module Autonomia::Agents::Operate::ChunkedDeliveryJob::TurnoDoPedaco
  private

  # Mesmo token-guard do ReplyJob: o último incoming da janela de debounce ainda é o nosso?
  # Sem stamp (conversa sem debounce, ex.: caminho de teste) -> considera válido (não aborta).
  # #3225: a mensagem mais nova que o turno leu no meio (as lidas do meta), ainda sem resposta própria, não o supera
  # (o mesmo critério do ReplyJob.turno_superado?). Sem lidas, o de sempre.
  def current_turn?(conversation, reply_to_message_id, meta = {}, agent = nil)
    stamp = conversation.reload.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
    pending = stamp.is_a?(Hash) ? stamp['pending_message_id'] : nil
    pending.blank? || pending == reply_to_message_id ||
      ::Autonomia::Agents::Operate::LeituraNoTurno.cobre?(conversation, pending, Array(meta.to_h['lidas_no_turno']), agent)
  end

  def bot_in_command?(conversation, agent_inbox = nil)
    # Revalida o CONTRATO INTEIRO com estado fresco, na MESMA caixa do agente (cada chunk):
    # sem responsável + agente ligado/ativo/não-interno/não-sistema + feature on + allowlist.
    ::Autonomia::Agents::Operate.no_comando?(conversation, agent_inbox)
  end

  # #3225: no 1º pedaço, com a flag, uma resposta deste agente já leu esta mensagem no meio do turno dela e saiu.
  def respondida_junto?(conversation, agent_inbox, reply_to_message_id, index)
    index.zero? && ::Autonomia::Agents::Operate::LeituraNoTurno.respondida_junto?(conversation, reply_to_message_id, agent_inbox.agent)
  end

  # O rastro da parada `respondida_junto`: o mesmo do settle e da hora de postar, na etapa dos pedaços.
  def rastro_de_respondida_junto(conversation, reply_to_message_id)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:respondida_junto, conversation_id: conversation.id,
                                                                                 msg: reply_to_message_id, etapa: 'pedaco')
  end
end
