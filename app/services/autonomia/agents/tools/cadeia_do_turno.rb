# A CADEIA DE ENTREGA HUMANIZADA DO TURNO QUE ABRIU A EXECUÇÃO AINDA ESTÁ EM CURSO? (#313)
#
# Duas perguntas iguais moram aqui: a do publicador de arquivo (`AsyncPublisher`), que não anexa o PDF no meio da
# frase que a Lia ainda está "digitando", e a do turno de evento (`Operate::EventoJob`), que não fala no meio dela.
# A cadeia carimba `autonomia_chunk_token` = "<reply_to>:<índice>"; se o ÚLTIMO índice esperado ainda não
# apareceu, ela não terminou.
module Autonomia::Agents::Tools::CadeiaDoTurno
  module_function

  def aberta?(run, conversation)
    expected = run.expected_chunks.to_i
    # `expected == 1` TAMBÉM espera: um pedaço único não foi postado, está agendado com atraso de até 15s. Só `0`
    # (caminho clássico e de voz, que postam de forma síncrona antes do despacho) dispensa.
    return false if expected < 1 || run.origin_message_id.blank?

    !pedaco_postado?(run, conversation, expected - 1)
  end

  def pedaco_postado?(run, conversation, index)
    token = "#{run.origin_message_id}:#{index}"
    conversation.messages.outgoing.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .any? { |message| message.content_attributes.to_h['autonomia_chunk_token'].to_s == token }
  end
end
