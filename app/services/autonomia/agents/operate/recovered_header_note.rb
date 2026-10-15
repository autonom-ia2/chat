# chat#1489: mensagem de modelo recuperada do celular pelo WhatsApp API com um arquivo no cabeçalho
# (`hybrid_recovery_header`), que não foi baixado. A IA fica sabendo por uma linha no HISTÓRICO, que é só contexto do
# modelo: nunca vai ao `content` da Message nem à resposta ao cliente. Se o modelo repetir a linha, ela sai da resposta
# antes da entrega; sobrando nada, o turno fica em silêncio (resposta vazia).
module Autonomia::Agents::Operate::RecoveredHeaderNote
  NOTES = {
    'image' => '[a mensagem tinha uma imagem que não foi lida]',
    'media' => '[a mensagem tinha um arquivo que não foi lido]'
  }.freeze

  module_function

  # O texto da mensagem para o histórico da IA.
  def history_content(message)
    note = NOTES[message.content_attributes.to_h['hybrid_recovery_header']]
    [message.content.to_s, note].compact.join("\n")
  end

  # A resposta do modelo sem as linhas de contexto. Sem linha nenhuma, o mesmo objeto.
  def without_notes(result)
    return result if result.nil? || result.reply.blank?

    reply = NOTES.values.reduce(result.reply.to_s) { |text, note| text.gsub(note, '') }.strip
    return result if reply == result.reply.to_s

    ::Autonomia::Agents::AnswerResult.new(
      reply: reply, confidence: result.confidence, handoff: result.handoff, used_knowledge: result.used_knowledge,
      answered_from_knowledge: result.answered_from_knowledge, raw_reply: result.raw_reply, error: result.error
    )
  end
end
