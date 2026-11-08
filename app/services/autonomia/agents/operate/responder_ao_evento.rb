# O RESPONDER RODANDO PARA UM EVENTO DA COTAÇÃO, e não para uma mensagem do cliente (PR C).
#
# É o mesmo turno do atendimento — a mesma instrução, o mesmo histórico público, os mesmos especialistas, a
# mesma conferência de preços e da fala, a mesma elegibilidade conferida com estado fresco e a mesma postagem
# sob o lock —, com seis diferenças, e cada uma tem motivo:
#
#   1. A "pergunta" é a NOTA DO SISTEMA do evento (`Tools::Evento#nota_do_sistema`), escrita para deixar claro
#      que não é a pessoa falando. Não há mídia do turno: ninguém mandou nada agora.
#   2. O contexto de entrega carrega o evento, e a ferramenta assíncrona RECUSA abrir cotação nova nele
#      (`Tools::Bound#async_refusal`, motivo `turno_de_evento`). A Lia pode consultar o especialista e ler o
#      resultado; não pode transformar um aviso do sistema num pedido que a pessoa não fez.
#   3. A entrega é UMA mensagem (o caminho clássico). A humanizada depende de uma mensagem de origem
#      (`ChunkedDeliveryJob#current_turn?`), e o turno de evento não tem uma; a de voz, de áudio do cliente.
#   4. A idempotência é a MARCA do evento na mensagem (`Tools::Evento::CHAVE`), não o id da mensagem de origem:
#      um retry do job, ou um evento duplicado, encontra a mensagem e não posta de novo.
#   5. A porta de engajamento não se aplica: o evento é continuação de um pedido que a pessoa já fez.
#   6. O sinal de passar segue passando a conversa (`bot_handoff!`), com a flag `agente_so_informa` (#2154) ou sem ela.
#
# O SILÊNCIO AQUI É FALHA, não decisão: IA indisponível, resposta vazia ou o sinal de silêncio voltam como
# `silenced` com o motivo, e quem decide a nova tentativa e a escalada é o `EventoJob`.
class Autonomia::Agents::Operate::ResponderAoEvento < Autonomia::Agents::Operate::Responder
  def initialize(conversation:, agent_inbox:, evento:)
    super(conversation: conversation, agent_inbox: agent_inbox)
    @evento = evento
  end

  # -> Result: `replied` (postou, ou a mensagem do evento já estava lá) ou `silenced` com o motivo em `error`
  # (`nao_elegivel`, `sinal`, `ia_falhou`, `vazio`, `falhou`).
  def perform
    return silencio_por_inelegibilidade unless still_eligible?

    result = answer
    motivo = motivo_do_silencio(result)
    return silencio(motivo) if motivo.present?

    outcome = classic_deliver(result)
    return outcome unless outcome.status == :replied

    enfileirar_cartoes(outcome) # #1479 F3: os cartões marcados no turno, depois que a mensagem sair
    handoff_if_signaled(result)
    outcome
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] turno falhou agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
    silencio('falhou')
  end

  private

  # #2154: o evento da cotação fica fora da regra "o agente só informa". Com a flag ligada ou não, o sinal da instrução
  # no evento segue passando a conversa (`bot_handoff!`), como antes.
  def agente_so_informa?
    false
  end

  def silencio(motivo)
    registrar_silencio(motivo)
    descartar_cartoes(motivo) # #1479 F3: o cartão marcado num turno sem resposta não sai
    Result.new(status: :silenced, error: motivo)
  end

  def silencio_por_inelegibilidade
    silencio('nao_elegivel')
  end

  def query
    @evento.nota_do_sistema
  end

  def media
    ::Autonomia::Agents::Operate::MessageMedia::EMPTY
  end

  def delivery
    @delivery ||= ::Autonomia::Agents::Tools::Delivery.new(conversation: @conversation, agent_inbox: @agent_inbox,
                                                           evento: @evento.tipo, execucao_do_evento: @evento.run)
  end

  def already_replied?
    @evento.publicado?(@conversation)
  end

  # `interacao` (#1479): a mesma do turno do cliente (`com_interacao`). `cartoes` (#1479 F3): os do turno, que fazem desta
  # mensagem a âncora deles (`Responder#ancora!`).
  def post_reply!(text, interacao = nil, cartoes: {})
    content, formato = com_interacao(text, interacao)
    mensagem = Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: content, message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: { 'autonomia_agent_id' => @agent.id, ::Autonomia::Agents::Tools::Evento::CHAVE => @evento.marca }
                              .merge(formato).merge(cartoes)
      )
    ).perform
    ancora!(mensagem, cartoes)
  end
end
