# chat#1489: mensagem recuperada do celular pelo WhatsApp API com um arquivo que não foi baixado (imagem no cabeçalho do
# modelo, ou mídia da qual só veio a legenda): `hybrid_recovery_header` = image | media. A IA fica sabendo por uma linha
# no HISTÓRICO, que é só contexto do modelo: nunca vai ao `content` da Message nem à resposta ao cliente. Se o modelo
# repetir a linha, ela sai da resposta antes da entrega (só a linha exata, sem padrão de texto); sobrando nada, o turno
# fica em silêncio com motivo próprio (SILENCE_REASON).
module Autonomia::Agents::Operate::RecoveredHeaderNote
  NOTES = {
    'image' => '[contexto interno, não repetir ao cliente: a mensagem tinha uma imagem que não foi lida]',
    'media' => '[contexto interno, não repetir ao cliente: a mensagem tinha um arquivo que não foi lido]'
  }.freeze
  SILENCE_REASON = 'so_contexto_interno'.freeze

  module_function

  # O texto da mensagem para o histórico da IA.
  def history_content(message)
    note = NOTES[message.content_attributes.to_h['hybrid_recovery_header']]
    [message.content.to_s, note].compact.join("\n")
  end

  # A resposta do modelo sem as linhas de contexto. Sem linha nenhuma, o mesmo objeto.
  def without_notes(result)
    return result if result.nil? || result.reply.blank?

    reply = clean(result.reply.to_s)
    return result if reply == result.reply.to_s

    ::Autonomia::Agents::AnswerResult.new(
      reply: reply, confidence: result.confidence, handoff: result.handoff, used_knowledge: result.used_knowledge,
      answered_from_knowledge: result.answered_from_knowledge, raw_reply: result.raw_reply, error: result.error
    )
  end

  # O motivo do silêncio quando a resposta era só a linha de contexto; nil nos outros casos.
  def silence_reason(answered, delivered)
    return if answered.nil? || answered.reply.blank?

    SILENCE_REASON if delivered.reply.blank?
  end

  # Tira a linha de cada trecho em que ela aparece, junta o espaço duplo que sobra ali e descarta o trecho vazio.
  # Os demais trechos ficam intactos.
  def clean(text)
    lines = text.split("\n", -1).map { |line| without_note(line) }
    lines.compact.join("\n").strip
  end

  def without_note(line)
    return line unless NOTES.values.any? { |note| line.include?(note) }

    cleaned = NOTES.values.reduce(line) { |text, note| text.gsub(note, '') }
    cleaned = cleaned.gsub('  ', ' ') while cleaned.include?('  ')
    cleaned.strip.presence
  end
end
