# QUANDO A LIA NÃO FALA SOBRE UM EVENTO DA COTAÇÃO, QUEM FICA SABENDO É O ATENDENTE (PR C).
#
# Dois caminhos, e nenhum deles escreve ao cliente:
#   - `notar`: a conversa tem humano no comando, ou o agente deixou de poder falar. O modelo não roda; o
#     evento vira NOTA PRIVADA, para quem está atendendo saber o que aconteceu com a cotação.
#   - `escalar`: o turno do evento falhou duas vezes. A conversa é liberada para a equipe pelo mesmo caminho
#     do handoff sinalizado pela instrução (`bot_handoff!` sob o lock, só com o espelho no comando;
#     `CONVERSATION_BOT_HANDOFF` faz o `NotificationListener` avisar a caixa), com o evento registrado como
#     `handed_off`, e a mesma nota privada.
#
# A NOTA CARREGA A MARCA DO EVENTO (`Tools::Evento::CHAVE`): é por ela que um retry não a duplica, e que o
# evento de fecho sabe que o de começo já teve desfecho. O texto é para o ATENDENTE, nunca para o cliente.
class Autonomia::Agents::Operate::AvisoAoAtendente
  # Por que a nota existe, em rótulo nosso de lista fechada.
  MOTIVOS = {
    'inelegivel' => 'A IA não falou com o cliente sobre isto: a conversa está com um atendente, ou o agente não pode ' \
                    'responder agora.',
    'ia_falhou' => 'A IA tentou falar com o cliente sobre isto duas vezes e não conseguiu. A conversa foi passada para a ' \
                   'equipe.'
  }.freeze

  def initialize(evento:)
    @evento = evento
    @run = evento.run
    @conversation = evento.run.conversation
  end

  # -> a nota criada, ou nil (já existia uma mensagem com a marca, ou não há conversa). Nunca levanta.
  def notar(motivo)
    return nil if @conversation.blank?

    nota = nil
    @conversation.with_lock { nota = postar_nota(motivo) unless @evento.publicado?(@conversation) }
    Rails.logger.info("[autonomia][evento] nota ao atendente run=#{@run.id} tipo=#{@evento.tipo} motivo=#{motivo}") if nota
    nota
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] nota ao atendente falhou run=#{@run.id} #{e.class}")
    nil
  end

  # Libera a conversa para a equipe (só enquanto o espelho deste vínculo ainda está no comando) e deixa a nota.
  # O handoff é conferido e feito sob o lock, como em `Responder#handoff_if_signaled`: duas passadas não o
  # duplicam, e o evento `handed_off` sai uma vez.
  def escalar(agent_inbox)
    liberou = false
    @conversation.with_lock do
      if @conversation.assignee_agent_bot_id == agent_inbox.agent_bot_id || @conversation.pending?
        @conversation.bot_handoff!
        liberou = true
      end
    end
    if liberou
      ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: agent_inbox.agent, conversation: @conversation, result: nil,
                                                           reason: 'ai_unavailable')
    end
    notar('ia_falhou')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] escalada falhou run=#{@run.id} #{e.class}")
    notar('ia_falhou')
  end

  private

  def postar_nota(motivo)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: texto(motivo), message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: @run.agent_inbox&.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => @run.autonomia_agent_id, ::Autonomia::Agents::Tools::Evento::CHAVE => @evento.marca }
      )
    ).perform
  end

  def texto(motivo)
    [
      "Aviso da cotação (execução #{@run.id}): #{::Autonomia::Agents::Tools::Evento::DESCRICOES.fetch(@evento.tipo, @evento.tipo)}",
      (@evento.fatos if @evento.fatos),
      MOTIVOS.fetch(motivo, MOTIVOS['inelegivel'])
    ].compact.join("\n")
  end
end
