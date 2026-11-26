# QUANDO A BIA NÃO FALA SOBRE O PAGAMENTO, QUEM FICA SABENDO É A EQUIPE (#3246b). Par do `AvisoAoAtendente` da Lia, para
# o evento que nasce da proposta (`Tools::EventoDaViagem`), e não de uma execução. A Lia fica como estava.
#
# Dois caminhos, e nenhum escreve ao cliente:
#   - `notar`: a conversa tem humano no comando, o agente não pode falar, a janela do canal fechou, a IA decidiu calar
#     ou a proposta paga foi trocada por outra. O evento vira NOTA PRIVADA, com os fatos (sem o link);
#   - `escalar`: o turno do evento falhou duas vezes. A conversa é liberada para a equipe como no `AvisoAoAtendente`
#     (`bot_handoff!` sob o lock, só com o espelho no comando, e o evento `handed_off`), e a mesma nota.
#
# A NOTA CARREGA A MARCA DO EVENTO (`EventoDaViagem::CHAVE`), conferida sob o lock da conversa: o retry não a duplica, e
# o evento que já teve nota não fala depois. O texto é para a EQUIPE, nunca para o cliente.
class Autonomia::Agents::Operate::AvisoDaViagem
  MOTIVOS = {
    'inelegivel' => 'A IA não falou com o cliente sobre isto: a conversa está com um atendente, ou o agente não pode ' \
                    'responder agora.',
    'silencio' => 'A IA decidiu não falar com o cliente sobre isto agora. Confira a conversa se precisar retomar.',
    'ia_falhou' => 'A IA tentou falar com o cliente sobre isto duas vezes e não conseguiu. A conversa foi passada para a ' \
                   'equipe.',
    'fora_da_janela' => 'A IA não pode escrever ao cliente agora: a janela do canal está fechada. O voucher sai quando o ' \
                        'cliente voltar a escrever e a IA conferir o pagamento.',
    'carrinho_substituido' => 'Este carrinho foi pago, mas a proposta da conversa já tinha sido trocada por outra. O ' \
                              'voucher deste pagamento não foi enviado; confira com a seguradora.'
  }.freeze
  CABECALHO = {
    ::Autonomia::Agents::Tools::EventoDaViagem::PAGAMENTO_CONFIRMADO => 'Pagamento do seguro viagem confirmado',
    ::Autonomia::Agents::Tools::EventoDaViagem::LEMBRETE => 'Seguro viagem ainda não pago'
  }.freeze

  def initialize(evento:)
    @evento = evento
    @conversation = evento.conversation
  end

  # -> a nota criada, ou nil (já existia mensagem com a marca, ou não há conversa). Nunca levanta.
  def notar(motivo)
    return nil if @conversation.blank?

    nota = nil
    @conversation.with_lock { nota = postar_nota(motivo) unless @evento.publicado?(@conversation) }
    Rails.logger.info("[autonomia][evento_da_viagem] nota cotacao=#{@evento.cotacao.id} tipo=#{@evento.tipo} motivo=#{motivo}") if nota
    nota
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][evento_da_viagem] nota falhou cotacao=#{@evento.cotacao&.id} #{e.class}")
    nil
  end

  # Libera a conversa para a equipe (só enquanto o espelho deste vínculo comanda) e deixa a nota.
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
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][evento_da_viagem] escalada falhou cotacao=#{@evento.cotacao.id} #{e.class}")
    notar('ia_falhou')
  end

  private

  def postar_nota(motivo)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: texto(motivo), message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: ::Autonomia::Agents::QuemResponde.agent_inbox(@conversation)&.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => @evento.cotacao.autonomia_agent_id,
                              ::Autonomia::Agents::Tools::EventoDaViagem::CHAVE => @evento.marca }
      )
    ).perform
  end

  def texto(motivo)
    [
      "#{CABECALHO.fetch(@evento.tipo, @evento.tipo)}: #{@evento.fatos(com_link: false)}",
      MOTIVOS.fetch(motivo, MOTIVOS['inelegivel'])
    ].join("\n")
  end
end
