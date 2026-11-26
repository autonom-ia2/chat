# O TURNO DA BIA ACIONADO PELO AVISO DE PAGAMENTO (#3246b). É o turno de evento da Lia (`ResponderAoEvento`: a nota do
# sistema no lugar da pergunta, uma mensagem só, sem a porta de engajamento, o silêncio como falha), herdado, com cinco
# diferenças, todas nesta classe (a Lia não muda):
#
#   1. O evento é o da proposta (`Tools::EventoDaViagem`), sem execução. O contexto de entrega leva a marca dele
#      (`Delivery#marca_do_evento`), e continua sendo turno de evento: nenhuma ferramenta abre cotação, marca reunião ou
#      gera proposta nele (`gerar_proposta_seguro_viagem` recusa).
#   2. O cartão do voucher NÃO entra marcado: no `pagamento_confirmado` o modelo é obrigado a chamar
#      `situacao_do_pagamento` (a nota do sistema pode ser imitada pelo cliente), e só ela marca o cartão, quando dá
#      "pago" e o voucher ainda não saiu. Ele sai depois da fala pelo caminho de cartões de sempre (`CartoesDoTurno`).
#   3. A fala grava a marca em `EventoDaViagem::CHAVE`. Quando a guarda da hora de postar acha a fala já postada (outro
#      run do mesmo evento chegou antes, entre a conferência do job e o lock), a âncora é procurada por ela
#      (`ancora_do_retry`), para o cartão que não chegou a ser enfileirado sair (o token barra o repetido). A nova
#      tentativa que já começa com a fala postada nem chega aqui: o `EventoDaViagemJob` reenfileira o cartão pela âncora.
#   4. Na hora de postar (sob o lock da conversa), o `pagamento_confirmado` também cala quando o voucher já saiu ou o
#      turno do cliente já o marcou e postou a âncora com ele (`EventoDaViagem#voucher_coberto_agora?`, com a proposta
#      relida): o cliente perguntou "caiu?" enquanto o aviso esperava a IA, e o segundo "confirmado" e o segundo PDF não
#      saem.
#   5. A fala nova do `pagamento_confirmado` que saiu sem o cartão do voucher marcado neste turno (o modelo não chamou
#      `situacao_do_pagamento`, ou ela não deu "pago"), com o voucher ainda não coberto na proposta relida: nota à
#      equipe (`AvisoDaViagem#notar_sem_voucher`). Sem ela, o cliente pago ficaria sem voucher e ninguém saberia.
class Autonomia::Agents::Operate::ResponderAoEventoDaViagem < Autonomia::Agents::Operate::ResponderAoEvento
  private

  def delivery
    @delivery ||= ::Autonomia::Agents::Tools::Delivery.new(conversation: @conversation, agent_inbox: @agent_inbox,
                                                           evento: @evento.tipo, marca_do_evento: @evento.marca)
  end

  def post_reply!(text, interacao = nil, cartoes: {})
    content, formato = com_interacao(text, interacao)
    mensagem = Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: content, message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: { 'autonomia_agent_id' => @agent.id, ::Autonomia::Agents::Tools::EventoDaViagem::CHAVE => @evento.marca }
                              .merge(formato).merge(cartoes)
      )
    ).perform
    ancora!(mensagem, cartoes)
  end

  def already_replied?
    super || @evento.voucher_coberto_agora?
  end

  # Depois da fala e do commit (`ResponderAoEvento#perform`), com os cartões que o turno marcou em mãos.
  def enfileirar_cartoes(outcome)
    super
    return unless outcome.message.present? && @evento.pagamento_confirmado? && !voucher_marcado_no_turno?
    return if @evento.voucher_coberto_agora?

    ::Autonomia::Agents::Operate::AvisoDaViagem.new(evento: @evento).notar_sem_voucher
  end

  def voucher_marcado_no_turno?
    voucher = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher
    Array(@delivery&.cartoes).any? { |cartao| voucher.cartao?(cartao) && cartao['chave'].to_s == @evento.cotacao.id.to_s }
  end

  def ancora_do_retry
    mensagem = @evento.mensagem(@conversation)
    mensagem if mensagem && !mensagem.private
  end
end
