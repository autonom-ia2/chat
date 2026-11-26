# OS CARTÕES DO ÚLTIMO PEDAÇO (#1479 F3), juntos: o descarte quando a cadeia para antes dele, o reenfileiramento no retry
# do pedaço que já entrou e (#3258) o comparativo segurado quando o cliente escreveu no meio da fala
# (`Operate::ComparativoSegurado`).
module Autonomia::Agents::Operate::ChunkedDeliveryJob::CartoesDoPedaco
  private

  # #1479 F3: a cadeia parou antes de postar o pedaço que leva os cartões (o último): eles não saem. Registro com o
  # motivo da parada, só quando o turno tinha cartão. O retry de um pedaço já postado (`ja_postado`) e o fim da cadeia
  # (`sem_pedaco`) não descartam.
  def descartar_cartoes(conversation, agent_inbox, reply_to_message_id, chunks, motivo)
    return if %i[ja_postado sem_pedaco].include?(motivo)
    return if Array(chunks.last.to_h.dig('marca', ::Autonomia::Agents::Operate::CartoesDoTurno::NA_ANCORA)).empty?

    ::Autonomia::Agents::Operate::CartoesDoTurno.descartados(conversation_id: conversation.id, agent: agent_inbox.agent.id,
                                                             msg: reply_to_message_id, motivo: motivo)
  end

  # #1479 F3: o retry do pedaço que leva os cartões e já entrou (`ja_postado`). O job anterior pode ter morrido entre
  # postar o pedaço e enfileirar os cartões: enfileira de novo para o pedaço gravado. O job dos cartões é idempotente
  # (token e desistência gravada), então o cartão sai uma vez só; o comparativo segurado fica fora da lista dele.
  # #3258: no retry do último pedaço, o fim do turno de novo (o anterior pode ter morrido antes dele; ele é idempotente).
  def reenfileirar_cartoes(conversation, agent_inbox, reply_to_message_id, chunks, index)
    chunk = chunks[index]
    ultimo = chunks[index + 1].blank?
    unless Array(chunk.to_h.dig('marca', ::Autonomia::Agents::Operate::CartoesDoTurno::NA_ANCORA)).empty?
      ::Autonomia::Agents::Operate::CartoesDoTurno.enfileirar(chunk_message(conversation, reply_to_message_id, index))
    end
    ::Autonomia::Agents::Operate::ComparativoSegurado.no_fim_do_turno(conversation, agent_inbox.agent, reply_to_message_id) if ultimo
  end

  # #3258: sob o lock, antes de postar o pedaço que leva o comparativo, a `motivo_da_parada` já passou. Se ainda assim uma
  # mensagem nova do cliente mudou o turno (o mesmo `current_turn?`, com as lidas), é porque a fala já começou e deixou de
  # conferi-lo (`FalaDaCadeia.comecada?`): o texto sai, e o comparativo fica segurado na mensagem até o fim do turno
  # seguinte. No 1º pedaço, ou sem a entrega inteira, o turno conferido é este, e nada fica segurado. Sem a flag, o pedaço
  # como veio (nem confere o turno de novo).
  def com_o_comparativo_segurado(conversation, agent_inbox, reply_to_message_id, chunk, meta)
    segurado = ::Autonomia::Agents::Operate::ComparativoSegurado
    return chunk unless segurado.pode_segurar?(chunk, agent_inbox.agent, conversation)
    return chunk if current_turn?(conversation, reply_to_message_id, meta, agent_inbox.agent)

    segurado.segurar(chunk)
  end

  # #1479 F3: o último pedaço é a âncora dos cartões. #3258: a linha do comparativo que ele segurou.
  def enfileirar_os_cartoes(posted)
    ::Autonomia::Agents::Operate::ComparativoSegurado.segurou(posted)
    ::Autonomia::Agents::Operate::CartoesDoTurno.enfileirar(posted)
  end
end
