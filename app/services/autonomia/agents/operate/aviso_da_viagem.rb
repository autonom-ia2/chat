# QUANDO A BIA NÃO FALA SOBRE O PAGAMENTO, QUEM FICA SABENDO É A EQUIPE (#3246b). Par do `AvisoAoAtendente` da Lia, para
# o evento que nasce da proposta (`Tools::EventoDaViagem`), e não de uma execução. A Lia fica como estava.
#
# Dois caminhos, e nenhum escreve ao cliente:
#   - `notar`: a conversa tem humano no comando, o agente não pode falar, a janela do canal fechou, a IA decidiu calar,
#     a IA falhou no lembrete, ou a proposta paga foi trocada por outra. O evento vira NOTA PRIVADA, com os fatos (sem o
#     link; na proposta trocada, sem fatos: os guardados são os da proposta nova);
#   - `notar_sem_voucher`: a fala do `pagamento_confirmado` saiu, mas o turno não marcou o voucher. A nota tem marca
#     própria, porque a fala já tem a do evento;
#   - `escalar`: o turno do `pagamento_confirmado` falhou duas vezes. A conversa é liberada para a equipe como no
#     `AvisoAoAtendente` (`bot_handoff!` sob o lock, só com o espelho no comando, e o evento `handed_off`), e a nota.
#
# Os textos ficam no catálogo (`NOTAS`, en e pt_BR). No `pagamento_confirmado`, a nota sempre diz que o pagamento foi
# confirmado e que o voucher NÃO foi enviado, e o que a equipe faz.
#
# A NOTA CARREGA A MARCA DO EVENTO (`EventoDaViagem::CHAVE`), conferida sob o lock da conversa: o retry não a duplica, e
# o evento que já teve nota não fala depois. O texto é para a EQUIPE, nunca para o cliente.
class Autonomia::Agents::Operate::AvisoDaViagem
  # Os textos (en e pt_BR), por tipo de evento e motivo: `<tipo>.cabecalho` (com os fatos) e `<tipo>.<motivo>`.
  NOTAS = 'autonomia.contratados.universal.notas.aviso_de_pagamento'.freeze
  MOTIVOS = %w[inelegivel silencio ia_falhou fora_da_janela carrinho_substituido sem_voucher].freeze
  # O sufixo da marca da nota do voucher que não foi: a fala do evento já tem a marca dele.
  SEM_VOUCHER = 'sem_voucher'.freeze
  # A proposta paga foi trocada: os fatos guardados agora são os da proposta NOVA, e a nota não os mostra.
  SEM_FATOS = %w[carrinho_substituido].freeze

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

  # A fala do `pagamento_confirmado` saiu sem o voucher (o modelo não conferiu com `situacao_do_pagamento`, ou ela não
  # deu "pago"): nota à equipe, com marca própria (`<marca>:sem_voucher`), uma por evento, conferida sob o lock. -> a nota
  # ou nil. Nunca levanta.
  def notar_sem_voucher
    marca = "#{@evento.marca}:#{SEM_VOUCHER}"
    nota = nil
    @conversation.with_lock { nota = postar_nota(SEM_VOUCHER, marca) unless @evento.mensagem(@conversation, com_marca: marca) }
    Rails.logger.info("[autonomia][evento_da_viagem] nota cotacao=#{@evento.cotacao.id} tipo=#{@evento.tipo} motivo=#{SEM_VOUCHER}") if nota
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

  def postar_nota(motivo, marca = @evento.marca)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: texto(motivo), message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: ::Autonomia::Agents::QuemResponde.agent_inbox(@conversation)&.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => @evento.cotacao.autonomia_agent_id,
                              ::Autonomia::Agents::Tools::EventoDaViagem::CHAVE => marca }
      )
    ).perform
  end

  # No `pagamento_confirmado`, toda nota diz que o pagamento caiu e que o voucher NÃO foi enviado, e o que a equipe faz.
  def texto(motivo)
    motivo = 'inelegivel' unless MOTIVOS.include?(motivo)
    corpo = I18n.t("#{NOTAS}.#{@evento.tipo}.#{motivo}")
    return corpo if SEM_FATOS.include?(motivo)

    [I18n.t("#{NOTAS}.#{@evento.tipo}.cabecalho", fatos: @evento.fatos(com_link: false)), corpo].join("\n")
  end
end
