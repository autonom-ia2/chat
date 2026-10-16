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
  SKIPPED_REASON = 'recuperada_so_contexto'.freeze

  module_function

  # Os itens do histórico (`role`, `content`), um por mensagem e na mesma ordem, com a linha de contexto acrescentada
  # ao da mensagem recuperada. Vale para o histórico de sempre e para o da equipe (HistoricoDaEquipe, #1669).
  def com_contexto(itens, messages)
    itens.zip(messages).map do |item, message|
      note = message && NOTES[message.content_attributes.to_h['hybrid_recovery_header']]
      note ? item.merge(content: [item[:content].to_s, note].join("\n")) : item
    end
  end

  # Evento do agente (`skipped_recuperada_so_contexto`), para o silêncio por esse motivo aparecer na aba Desempenho.
  def registrar_silencio(motivo, agent:, conversation:)
    return unless motivo == SILENCE_REASON

    ::Autonomia::Agents::Operate::EventLogger.skipped(agent: agent, conversation: conversation, reason: SKIPPED_REASON)
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
  # Compara com a resposta crua: só quando ela trazia a linha e, sem ela, não sobrou nada.
  def silence_reason(answered, delivered)
    return if answered.nil? || answered.reply.blank?
    return unless NOTES.values.any? { |note| answered.reply.to_s.include?(note) }

    SILENCE_REASON if delivered.nil? || delivered.reply.blank?
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
