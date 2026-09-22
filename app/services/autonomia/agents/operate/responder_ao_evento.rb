# O RESPONDER RODANDO PARA UM EVENTO DA COTAÇÃO, e não para uma mensagem do cliente (PR C).
#
# É o mesmo turno do atendimento — a mesma instrução, o mesmo histórico público, os mesmos especialistas, a
# mesma conferência de preços e da fala, a mesma elegibilidade conferida com estado fresco e a mesma postagem
# sob o lock —, com cinco diferenças, e cada uma tem motivo:
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
    handoff_if_signaled(result) if outcome.status == :replied
    outcome
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] turno falhou agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
    silencio('falhou')
  end

  private

  def silencio(motivo)
    registrar_silencio(motivo)
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
                                                           evento: @evento.tipo)
  end

  def already_replied?
    @evento.publicado?(@conversation)
  end

  def post_reply!(text)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: text, message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: { 'autonomia_agent_id' => @agent.id, ::Autonomia::Agents::Tools::Evento::CHAVE => @evento.marca }
      )
    ).perform
  end
end
