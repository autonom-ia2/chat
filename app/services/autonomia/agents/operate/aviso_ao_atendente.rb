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
    'silencio' => 'A IA decidiu não falar com o cliente sobre isto agora. Confira a conversa se precisar retomar.',
    'ia_falhou' => 'A IA tentou falar com o cliente sobre isto duas vezes e não conseguiu. A conversa foi passada para a ' \
                   'equipe.',
    'consulta_antiga' => 'Esta consulta foi trocada por uma mais nova, mas também concluiu. O cliente não recebeu este ' \
                         'resultado; confira se o sistema da conta registrou o pedido duas vezes.',
    'consulta_fechada_concluiu' => 'Esta consulta foi dada como encerrada sem resposta, mas o sistema da conta respondeu ' \
                                   'depois. O cliente não recebeu este resultado; confira o pedido no sistema da conta.',
    'consulta_incerta' => 'O pedido saiu para o sistema da conta, mas a resposta se perdeu (o processo caiu no meio). A IA ' \
                          'não chamou de novo e vai dizer ao cliente que não conseguiu confirmar. Confira se o pedido foi ' \
                          'registrado.'
  }.freeze

  # #1430: a consulta HTTP que concluiu (2xx) fora do turno — superada por um pedido mais novo, ou fechada pelo varredor
  # antes da resposta. O sistema de fora fez o pedido, e quem atende precisa saber, com o resultado (`resultado`, quando
  # não é o gravado na linha); o cliente não ouve nada. Pelo mesmo `notar` (a marca do evento evita a nota em dobro).
  def self.consulta_antiga(run, motivo = 'consulta_antiga', resultado: nil)
    evento = ::Autonomia::Agents::Tools::Evento.new(run: run, tipo: ::Autonomia::Agents::Tools::Evento::CONSULTA_CONCLUIDA)
    fatos = resultado ? ::Autonomia::Agents::Tools::Evento.cercado(resultado) : :do_evento
    new(evento: evento, fatos: fatos).notar(motivo)
  end

  # #1430: a chamada saiu e a resposta se perdeu. A marca é a do tipo `incerta`, e não a do `consulta_falhou`: o evento
  # que fala com o cliente não pode tomar esta nota pela palavra dele.
  def self.consulta_incerta(run)
    new(evento: ::Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'incerta'), fatos: nil).notar('consulta_incerta')
  end

  # `fatos`: o que a nota mostra abaixo da descrição; por padrão, os do evento.
  def initialize(evento:, fatos: :do_evento)
    @evento = evento
    @run = evento.run
    @conversation = evento.run.conversation
    @fatos = fatos
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
      if ::Autonomia::Agents::Operate.espelho_no_comando?(@conversation, agent_inbox)
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

  # A da consulta HTTP (#1430) não fala em cotação, e os fatos dela são o resultado: é o que quem atende precisa ver.
  def descricao
    ::Autonomia::Agents::Tools::Evento::DESCRICOES.fetch(@evento.tipo, @evento.tipo)
  end

  def texto(motivo)
    [
      "Aviso da #{@run.consulta_http? ? 'consulta' : 'cotação'} (execução #{@run.id}): #{descricao}",
      (@fatos == :do_evento ? @evento.fatos : @fatos),
      MOTIVOS.fetch(motivo, MOTIVOS['inelegivel'])
    ].compact.join("\n")
  end
end
