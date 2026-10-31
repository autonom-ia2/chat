# #1630: o RESPONDER no turno da passagem para a IA (Operate::AoReceberPassagem: por uma pessoa, pela Atribuição do CRM
# ou por outro agente), sem mensagem nova do cliente. É o mesmo turno do atendimento, pelo mesmo `perform` (a mesma
# instrução, o mesmo histórico público — nota privada nunca vai ao modelo —, a mesma pergunta, as mesmas limpezas da
# resposta, a mesma elegibilidade conferida com estado fresco e a mesma postagem sob o lock), com estas diferenças, e
# cada uma tem motivo:
#
#   1. O contexto do turno diz ao modelo quem acabou de passar a conversa, e ensina o sinal de silêncio: o agente pode
#      não ter nada útil a dizer (quem atendia já resolveu tudo). O silêncio aqui é decisão.
#   2. A âncora é a passagem, não uma mensagem: a resposta leva `autonomia_passagem_id` (CHAVE), e é isso que impede
#      responder duas vezes à mesma passagem (`already_replied?`). Contra o settle atrasado da última mensagem do
#      cliente, este turno toma a posse dela (PosseDoTurno) antes da IA: quem chegar primeiro responde, o outro cala.
#   3. Desiste se o cliente escreveu depois da passagem (o turno normal da mensagem responde, com o contexto da
#      passagem) ou se uma pessoa voltou a escrever ao cliente depois dela (atendente responde, não assume). As duas
#      conferidas antes da IA e de novo na hora de postar.
#   4. Não devolve a conversa a humanos: nem pela porta de engajamento (fora do público ou do horário, só cala) nem
#      pelo pedido de passar a humanos do modelo. A conversa acabou de ser entregue a este agente, sem mensagem nova
#      do cliente.
#   5. Entrega numa mensagem (o caminho clássico): a humanizada e a de voz dependem de uma mensagem de origem.
#   6. Turno que falha (IA fora, resposta vazia, exceção) solta a posse da última mensagem do cliente que tomou, para o
#      turno dessa mensagem poder ser refeito (ReenfileirarTurno). Não reenfileira sozinho, e a chave da passagem fica
#      (AoReceberPassagem: a próxima tentativa só viria de outra passagem, com outra chave).
#   7. Sem as ferramentas que passam a conversa (`passa_a_conversa?`): o turno da passagem não abre assunto nem passa a
#      conversa adiante, então não há vai e volta entre agentes sem o cliente (Tools::Delivery#turno_da_passagem?).
class Autonomia::Agents::Operate::ResponderAPassagem < Autonomia::Agents::Operate::Responder
  CHAVE = 'autonomia_passagem_id'.freeze

  def initialize(conversation:, agent_inbox:, passagem:)
    super(conversation: conversation, agent_inbox: agent_inbox)
    @passagem = passagem
  end

  # -> Result
  def perform
    return silencio_da_passagem('cliente_escreveu') if cliente_escreveu_depois?
    return silencio_da_passagem('turno_em_curso') unless posse_da_ultima_mensagem?

    super
  end

  private

  def silencio_da_passagem(motivo)
    registrar_silencio(motivo)
    Result.silenced
  end

  # O sinal é a decisão do modelo (o que este turno existe para permitir) e vai também à telemetria do turno.
  def registrar_silencio(motivo)
    super
    return unless motivo == 'sinal'

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:sinal_na_passagem, conversation_id: @conversation.id,
                                                                                  passagem: @passagem.id, agent_inbox: @agent_inbox.id)
  end

  # A posse do turno da última mensagem do cliente (se houver), com valor próprio desta passagem: o mesmo job rodando de
  # novo a reconhece; o settle dessa mensagem que chegar depois não a toma (e vice-versa).
  def posse_da_ultima_mensagem?
    ultima = @conversation.messages.chat.incoming.reorder(:created_at, :id).last
    return true if ultima.nil?

    @ultima_id = ultima.id
    ::Autonomia::Agents::Operate::PosseDoTurno.tomar?(@conversation.id, @ultima_id, @agent_inbox.id, dono: valor_da_posse)
  end

  def valor_da_posse
    "passagem:#{@passagem.id}"
  end

  # O turno falhou (Responder#falha_no_turno, SILENCIOS_DE_FALHA): solta a posse da última mensagem que este turno tomou,
  # só se ainda for dele (compare-and-delete). Não reenfileira.
  def soltar_posse
    return if @ultima_id.nil?

    ::Autonomia::Agents::Operate::PosseDoTurno.soltar(@conversation.id, @ultima_id, @agent_inbox.id, valor_da_posse)
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

  def skip_for_humans(reason)
    registrar_silencio('fora_do_engajamento')
    Result.skipped(reason)
  end

  def handoff_if_signaled(_result)
    nil
  end

  def deliver(result)
    classic_deliver(result)
  end

  def media
    ::Autonomia::Agents::Operate::MessageMedia::EMPTY
  end

  # O contexto de entrega deste turno: ancorado na passagem e marcado como turno da passagem (sem as ferramentas que
  # passam a conversa adiante).
  def delivery
    @delivery ||= ::Autonomia::Agents::Tools::Delivery.new(conversation: @conversation, agent_inbox: @agent_inbox,
                                                           passagem: @passagem.id)
  end

  def already_replied?
    @conversation.messages.outgoing.where(sender_type: 'AgentBot').where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                 .any? { |message| message.content_attributes.to_h[CHAVE].to_s == @passagem.id.to_s }
  end

  # #1479: as mesmas opções e o mesmo link do turno normal (Responder#com_interacao), com a chave da passagem. F3: e os
  # cartões do turno, que fazem desta mensagem a âncora deles (`Responder#ancora!`).
  def post_reply!(text, interacao = nil, cartoes: {})
    content, formato = com_interacao(text, interacao)
    mensagem = Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: content, message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: { 'autonomia_agent_id' => @agent.id, CHAVE => @passagem.id }.merge(formato).merge(cartoes),
        **destinatarios_do_email # #1828: no e-mail, a resposta da passagem também mantém a cópia.
      )
    ).perform
    ancora!(mensagem, cartoes)
  end
end
