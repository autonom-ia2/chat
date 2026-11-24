# O TURNO QUE ENTREGOU A CONSULTA FOI SUPERADO? (#1430, `ConsultaNoTurno#entrega_deste_turno?`) Uma mensagem mais nova
# do cliente o superou, e ele não vai postar: o turno novo toma a entrega, para o resultado não se perder. O critério é
# o mesmo da hora de postar: `ReplyJob.turno_superado?`, que o `Responder#turno_superado?` usa (o stamp do debounce, com
# a Fase 2 ou com a fila do agente, #3211), e `ResponderAPassagem#turno_superado?` (o cliente escreveu depois da
# passagem). `quem`: o `Delivery#turno` gravado. O agente é o desta consulta (`@agente`, quem fala na conversa).
module Autonomia::Agents::Tools::ConsultaNoTurno::TurnoSuperado
  private

  # O turno que entregou não posta: uma mensagem mais nova do cliente o superou (o mesmo critério do
  # `Responder#turno_superado?` e do `ResponderAPassagem#turno_superado?`).
  def turno_superado?(quem)
    tipo, id = quem.to_s.split(':', 2)
    conversa = Conversation.find(@turno.conversation.id)
    case tipo
    when 'mensagem' then mensagem_superada?(conversa, id)
    when 'passagem' then passagem_superada?(conversa, id)
    else false
    end
  end

  def mensagem_superada?(conversa, message_id)
    ::Autonomia::Agents::Operate::ReplyJob.turno_superado?(conversa, message_id, @agente)
  end

  def passagem_superada?(conversa, passagem_id)
    passagem = ::Crm::Passagem.find_by(id: passagem_id, conversation_id: conversa.id)
    passagem.present? && conversa.messages.chat.incoming.exists?(['created_at > ?', passagem.em])
  end
end
