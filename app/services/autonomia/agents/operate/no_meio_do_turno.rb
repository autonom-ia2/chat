# O LADO DO RESPONDER NA LEITURA DO MEIO DO TURNO (#3225, `Operate::LeituraNoTurno`). Incluído no `Operate::Responder`:
# os prepends do WAHA (`Waha::RichNative::AgentTurnGuard`, `ResponderLocation`, `ResponderChoice`) ficam acima dele e
# alcançam `texto_no_meio_do_turno`, o único método que diz se uma mensagem do meio do turno é legível e o que a IA lê
# dela, com as mesmas regras com que limpam o histórico e a pergunta.
#
# - `leitura`: o leitor do turno, só no turno de uma mensagem do cliente (com âncora) e com a flag (`LeituraNoTurno.ligada?`).
#   O turno da passagem e o de evento não têm âncora: nunca leem. Sem leitor, o pedido ao modelo fica o de antes.
# - `respondida_junto?`: o turno desta mensagem já foi respondido por outro turno, que a leu (silêncio `respondida_junto`).
# - `marca_das_lidas` e `metadata_da_leitura`: o que a resposta grava e o que vai ao evento `replied`.
# - `fim_do_turno_com_segurado` (#3258): o turno acabou; o comparativo que uma fala anterior segurou sai ou é descartado.
module Autonomia::Agents::Operate::NoMeioDoTurno
  LeituraNoTurno = ::Autonomia::Agents::Operate::LeituraNoTurno
  # O mesmo texto da transcrição na pergunta do turno (`Responder#query`).
  AUDIO_TRANSCRITO = '[áudio do cliente, transcrito automaticamente]: '.freeze

  private

  def leitura
    return @leitura if defined?(@leitura)

    @leitura = (nova_leitura if @reply_to_message_id.present? && LeituraNoTurno.ligada?(@agent, @conversation))
  end

  # A âncora e a rajada que já foi na pergunta marcam onde a leitura começa.
  def nova_leitura
    LeituraNoTurno.new(conversation: @conversation, agent: @agent, delivery: delivery, ancora: @reply_to_message_id,
                       rajada: current_turn_incoming.map(&:id)) { |message| texto_no_meio_do_turno(message) }
  end

  # O texto de uma mensagem do cliente que chegou no meio do turno, com o tratamento da pergunta (a citação e a moldura
  # da equipe); nil quando ela não é legível: a recuperação do WhatsApp Híbrido pendente, o toque numa opção (que só a
  # pergunta do turno lê como dado), imagem, documento ou áudio sem transcrição. Os prepends do WAHA tiram também o que
  # tiram do histórico (a apagada, a visualização única, o voto retirado) e acrescentam o mapa e o voto.
  def texto_no_meio_do_turno(message)
    return if ::WhatsappHybrid::UnsupportedRecovery.pending?(message) || toque_numa_opcao?(message)

    corpo = corpo_no_meio_do_turno(message)
    return if corpo.blank?

    texto = [quoted_context(message), corpo].compact.join("\n")
    equipe.aplica? ? equipe.pergunta(texto, message) : texto
  end

  def toque_numa_opcao?(message)
    ::Autonomia::Agents::Interacao.opcao_tocada(message).present? && message.content_attributes.to_h['in_reply_to'].present?
  end

  # Só texto, ou áudio com todas as transcrições (o mesmo leitor de mídia do turno, com o cache dele). Outro anexo: nil.
  def corpo_no_meio_do_turno(message)
    anexos = message.attachments.to_a
    texto = message.content.to_s.strip.presence
    return texto if anexos.empty?
    return unless anexos.all? { |anexo| anexo.file_type.to_s == 'audio' } && ::Autonomia::Agents::Config.operate_media_enabled?(@agent)

    transcritos = ::Autonomia::Agents::Operate::MessageMedia.new(messages: [message], agent: @agent).extract.transcripts
    return unless transcritos.size == anexos.size

    [texto, *transcritos.map { |transcrito| "#{AUDIO_TRANSCRITO}#{transcrito}" }].compact.join("\n")
  end

  # Uma resposta deste agente já leu esta mensagem no meio do turno dela e saiu. Sem a flag, nem consulta.
  def respondida_junto?
    LeituraNoTurno.respondida_junto?(@conversation, @reply_to_message_id, @agent)
  end

  # Não é falha: o turno foi respondido, pelo turno que leu. A posse fica.
  def silencio_por_respondida_junto(etapa)
    registrar_silencio('respondida_junto')
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:respondida_junto, conversation_id: @conversation.id,
                                                                                 msg: @reply_to_message_id, etapa: etapa)
    self.class::Result.silenced
  end

  # O que a resposta grava, na mesma transação do post. {} sem lidas.
  def marca_das_lidas
    LeituraNoTurno.marca(@delivery&.lidas_no_turno)
  end

  def metadata_da_leitura
    @leitura ? @leitura.metadata : {}
  end

  # #3258: o turno da mensagem do cliente acabou com a resposta inteira (texto ou voz) ou com o sinal de silêncio: o
  # comparativo que uma fala anterior deste agente segurou sai depois desta resposta ou é descartado. Aqui só se
  # enfileira a decisão, com os ids (`ComparativoSegurado.decidir_depois`, só com a flag): ela não roda dentro do turno
  # nem do resgate dele. Na entrega em pedaços, quem enfileira é a cadeia, no último pedaço. O turno da passagem e o de
  # evento não têm âncora: nada aqui.
  def fim_do_turno_com_segurado
    ::Autonomia::Agents::Operate::ComparativoSegurado.decidir_depois(@conversation, @agent, @reply_to_message_id)
  end
end
