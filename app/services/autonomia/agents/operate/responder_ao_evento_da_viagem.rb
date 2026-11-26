# O TURNO DA BIA ACIONADO PELO AVISO DE PAGAMENTO (#3246b). É o turno de evento da Lia (`ResponderAoEvento`: a nota do
# sistema no lugar da pergunta, uma mensagem só, sem a porta de engajamento, o silêncio como falha), herdado, com três
# diferenças, todas nesta classe (a Lia não muda):
#
#   1. O evento é o da proposta (`Tools::EventoDaViagem`), sem execução. O contexto de entrega leva a marca dele
#      (`Delivery#marca_do_evento`), e continua sendo turno de evento: nenhuma ferramenta abre cotação, marca reunião ou
#      gera proposta nele (`gerar_proposta_seguro_viagem` recusa).
#   2. No `pagamento_confirmado`, o cartão do voucher (`SeguroViagem::EntregaDoVoucher`) já entra marcado: sai depois da
#      fala pelo caminho de cartões de sempre (`CartoesDoTurno`). Se o modelo também chamar `situacao_do_pagamento`, a
#      marca é a mesma (tipo e cotação) e sai um voucher só.
#   3. A fala grava a marca em `EventoDaViagem::CHAVE`. O retry que acha a fala já postada procura a âncora por ela
#      (`ancora_do_retry`), para o cartão que não chegou a ser enfileirado sair (o token barra o repetido).
class Autonomia::Agents::Operate::ResponderAoEventoDaViagem < Autonomia::Agents::Operate::ResponderAoEvento
  VOUCHER = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher

  private

  def delivery
    @delivery ||= ::Autonomia::Agents::Tools::Delivery.new(conversation: @conversation, agent_inbox: @agent_inbox,
                                                           evento: @evento.tipo, marca_do_evento: @evento.marca).tap do |entrega|
      entrega.marcar_cartao(VOUCHER.cartao(@evento.cotacao)) if @evento.pagamento_confirmado?
    end
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

  def ancora_do_retry
    mensagem = @evento.mensagem(@conversation)
    mensagem if mensagem && !mensagem.private
  end
end
