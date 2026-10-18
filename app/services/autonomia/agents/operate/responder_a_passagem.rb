# #1630: o RESPONDER no turno da passagem de uma pessoa para a IA (Operate::AoReceberPassagem), sem mensagem nova do
# cliente. É o mesmo turno do atendimento (a mesma instrução, o mesmo histórico público — nota privada nunca vai ao
# modelo —, a mesma pergunta, a mesma elegibilidade conferida com estado fresco e a mesma postagem sob o lock), com
# estas diferenças, e cada uma tem motivo:
#
#   1. O contexto do turno diz ao modelo que a conversa acabou de ser passada por uma pessoa, e ensina o sinal de
#      silêncio: o agente pode não ter nada útil a dizer (a pessoa já resolveu tudo). O silêncio aqui é decisão.
#   2. A âncora é a passagem, não uma mensagem: a resposta leva `autonomia_passagem_id` (CHAVE), e é isso que impede
#      responder duas vezes à mesma passagem (`already_replied?`).
#   3. Desiste se o cliente escreveu depois da passagem (o turno normal da mensagem responde, com o contexto da
#      passagem) ou se uma pessoa voltou a escrever ao cliente depois dela (atendente responde, não assume: ela está
#      atendendo). As duas conferidas antes da IA e de novo na hora de postar.
#   4. A porta de engajamento que bloqueia NÃO devolve a conversa a humanos: uma pessoa acabou de passá-la à IA. Só cala.
#   5. Entrega numa mensagem (o caminho clássico): a humanizada e a de voz dependem de uma mensagem de origem.
class Autonomia::Agents::Operate::ResponderAPassagem < Autonomia::Agents::Operate::Responder
  CHAVE = 'autonomia_passagem_id'.freeze

  def initialize(conversation:, agent_inbox:, passagem:)
    super(conversation: conversation, agent_inbox: agent_inbox)
    @passagem = passagem
  end

  # -> Result
  def perform
    return silencio_da_passagem('nao_elegivel') unless still_eligible?

    motivo = motivo_antes_da_ia
    return silencio_da_passagem(motivo) if motivo

    result = sem_marca_da_equipe(answer)
    motivo = motivo_do_silencio(result)
    return silencio_decidido(result, motivo) if motivo

    outcome = classic_deliver(result)
    depois_da_entrega(result, outcome)
    outcome
  rescue StandardError => e
    falha_no_turno(e)
  end

  private

  def motivo_antes_da_ia
    return 'cliente_escreveu' if cliente_escreveu_depois?
    return 'pessoa_respondeu' if pessoa_respondeu?

    'fora_do_engajamento' if ::Autonomia::Agents::Operate::EngagementGate.new(agent: @agent, conversation: @conversation).blocked_reason
  end

  def silencio_da_passagem(motivo)
    registrar_silencio(motivo)
    Result.silenced
  end

  # O silêncio depois da IA: o `sinal` é a decisão do modelo (o que este turno existe para permitir) e vai à telemetria.
  def silencio_decidido(result, motivo)
    if motivo == 'sinal'
      ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:sinal_na_passagem, conversation_id: @conversation.id,
                                                                                    passagem: @passagem.id, agent_inbox: @agent_inbox.id)
    end
    silence_with_async(result, motivo)
  end

  # A passagem deste turno, com o sinal de silêncio (no turno normal ela vem sem ele).
  def contexto_da_passagem
    ::Autonomia::Agents::Operate::AoReceberPassagem.contexto(@passagem, silencio: silence_tokens.first)
  end

  def cliente_escreveu_depois?
    @conversation.messages.chat.incoming.exists?(['created_at > ?', @passagem.em])
  end

  # Uma pessoa da equipe escreveu ao cliente depois da passagem (estado fresco).
  def pessoa_respondeu?
    @conversation.messages.chat.outgoing.where(sender_type: 'User').where('created_at > ?', @passagem.em)
                 .any? { |message| ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(message) && !message.failed? }
  end

  # Na hora de postar (dentro do lock): o cliente escreveu durante a IA. Responde o turno da mensagem nova.
  def turno_superado?
    cliente_escreveu_depois?
  end

  def media
    ::Autonomia::Agents::Operate::MessageMedia::EMPTY
  end

  def already_replied?
    @conversation.messages.outgoing.where(sender_type: 'AgentBot').where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                 .any? { |message| message.content_attributes.to_h[CHAVE].to_s == @passagem.id.to_s }
  end

  def post_reply!(text)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: text, message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: { 'autonomia_agent_id' => @agent.id, CHAVE => @passagem.id }
      )
    ).perform
  end
end
