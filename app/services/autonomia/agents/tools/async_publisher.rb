# PUBLICADOR da entrega assíncrona (#313).
#
# Separado do `Operate::Responder` de propósito. O Responder tem lógica de POSSE DO TURNO
# (`still_eligible?`, `already_replied?`) que aqui não se aplica: isto não é resposta a uma mensagem,
# é a entrega de algo que o cliente pediu e está esperando. Mas AUTORIZAÇÃO continua valendo inteira
# — quem publica sem checar kill-switch da conta, estado do agente e allowlist de piloto acaba
# falando com cliente real a partir de um agente que já foi desligado.
#
# TRÊS decisões que este arquivo carrega:
#
# 1. NUNCA carimba `autonomia_reply_to_message_id`. O `already_replied?` do Responder é um regex
#    sobre QUALQUER outgoing do bot com aquele id: uma entrega assíncrona que o herdasse faria o
#    Responder achar que o turno já respondeu e DESCARTAR a resposta real, em silêncio.
#
# 2. Com humano na conversa, publica como NOTA PRIVADA. O corretor recebe a cotação e decide como
#    apresentar; o cliente não recebe o robô falando por cima de quem já está atendendo.
#
# 3. ESPERA a cadeia de entrega humanizada drenar. Aquela cadeia pode durar até 90s encadeando até 5
#    mensagens; publicar no meio dela entrega "encontrei 3 opções" antes de "deixa eu consultar", e
#    ainda quebra a janela de mídia do turno seguinte (um outgoing entre duas incoming muda o que
#    `current_turn_incoming` considera turno atual).
class Autonomia::Agents::Tools::AsyncPublisher
  # Motivos de não-publicação, devolvidos a quem chamou (o job decide se re-agenda ou encerra).
  Result = Struct.new(:status, :message, keyword_init: true) do
    def published? = status == :published
    def deferred? = status == :deferred
    def blocked? = status == :blocked
  end

  def initialize(run:)
    @run = run
  end

  # -> Result. NUNCA levanta: falhar em publicar não pode derrubar a execução inteira.
  def publish(text, wait_for_chain: true)
    body = text.to_s.strip
    return Result.new(status: :skipped) if body.blank?

    conversation = authorized_conversation
    return Result.new(status: :blocked) if conversation.blank?
    return Result.new(status: :deferred) if wait_for_chain && humanized_chain_open?(conversation)

    post(conversation, authorized_inbox(conversation), body)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] publish failed run=#{@run.id} #{e.class}")
    Result.new(status: :blocked)
  end

  # Publica SEM esperar a cadeia de chunks drenar. Último recurso, usado quando o teto de adiamentos
  # estourou: mensagem fora de ordem é ruim, mensagem que nunca chega é pior — e uma cadeia que não
  # termina (o cliente escreveu no meio e ela foi abortada) travaria a entrega para sempre.
  def publish!(text)
    publish(text, wait_for_chain: false)
  end

  private

  # A conversa em que esta execução AINDA pode publicar, ou nil.
  #
  # Execução morta (supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da
  # conta) não publica: uma entrega adiada de uma cotação que o cliente já corrigiu sairia até 90s
  # depois, e ele receberia dois preços conflitantes. NÃO basta exigir `running?` — a entrega final
  # legítima é publicada e a linha fechada logo em seguida, então uma republicação adiada
  # encontraria a linha já `done`.
  def authorized_conversation
    return if @run.reload.dead?

    conversation = @run.conversation
    return if conversation.blank?
    return unless same_binding?(authorized_inbox(conversation))

    conversation
  end

  def authorized_inbox(conversation)
    @authorized_inbox ||= ::Autonomia::Agents::Operate.authorized_agent_inbox(conversation.reload)
  end

  # O vínculo autorizado agora é o MESMO que aceitou a execução? A conversa pode ter mudado de caixa
  # (ou o vínculo ter sido recriado) entre o disparo e a entrega — nesse caso a cotação não é mais
  # deste agente. Execução antiga sem `agent_inbox_id` gravado aceita qualquer vínculo autorizado.
  def same_binding?(agent_inbox)
    return false if agent_inbox.blank?

    @run.agent_inbox_id.blank? || @run.agent_inbox_id == agent_inbox.id
  end

  # Há uma cadeia de entrega humanizada em curso para o turno que originou esta execução? A cadeia
  # carimba `autonomia_chunk_token` = "<reply_to>:<índice>"; se o ÚLTIMO índice esperado ainda não
  # apareceu, ela não terminou.
  def humanized_chain_open?(conversation)
    expected = @run.expected_chunks.to_i
    # `expected == 1` TAMBÉM espera: um pedaço único não foi postado, está agendado com atraso de até
    # 15s. Só `0` (caminho clássico e de voz, que postam de forma síncrona antes do despacho) dispensa.
    return false if expected < 1 || @run.origin_message_id.blank?

    !chunk_posted?(conversation, expected - 1)
  end

  def chunk_posted?(conversation, index)
    token = "#{@run.origin_message_id}:#{index}"
    conversation.messages.outgoing.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .any? { |message| message.content_attributes.to_h['autonomia_chunk_token'].to_s == token }
  end

  # Publica sob lock da conversa, com idempotência pelo CONTEÚDO da entrega — retry do Sidekiq, ou
  # consulta que reemite a mesma lista, encontra a mensagem já postada e não duplica. Sem `return`
  # dentro do bloco (dispararia ROLLBACK e descartaria a mensagem recém-criada), como no operate.
  #
  # A leitura da sequência e o avanço ficam DENTRO do lock: dois
  # publicadores concorrentes (duas entregas parciais adiadas com o mesmo atraso, duas threads da
  # fila) liam o mesmo número, e o segundo via a posição ocupada, descartava o texto e ainda
  # devolvia sucesso — a segunda cotação sumia sem ninguém notar.
  def post(conversation, agent_inbox, body)
    posted = nil
    conversation.with_lock do
      @run.reload
      sequence = @run.sequence
      if delivery_posted?(conversation, body)
        posted = :duplicate
      else
        posted = build_message!(conversation, agent_inbox, sequence, body)
        # Só avança quando uma mensagem NOVA entrou: como a idempotência é pelo conteúdo, o
        # duplicado não ocupa posição nenhuma, e avançar nele faria o contador mentir sobre
        # quantas mensagens a execução publicou.
        @run.advance_sequence!(sequence)
      end
    end
    Result.new(status: :published, message: (posted unless posted == :duplicate))
  end

  def delivery_posted?(conversation, body)
    token = @run.delivery_token(body)
    conversation.messages.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .any? { |message| message.content_attributes.to_h['autonomia_async_token'].to_s == token }
  end

  def build_message!(conversation, agent_inbox, sequence, body)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: body,
        # Com responsável na conversa a entrega vira NOTA PRIVADA: quem fala com o cliente é a
        # pessoa que assumiu, e ela precisa do dado — não do robô por cima dela.
        message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: agent_inbox.agent_bot_id, private: conversation.assignee_id.present?,
        content_attributes: {
          autonomia_agent_id: agent_inbox.agent.id,
          autonomia_async_token: @run.delivery_token(body),
          autonomia_async_slug: @run.slug,
          autonomia_async_sequence: sequence
        }
      )
    ).perform
  end
end
