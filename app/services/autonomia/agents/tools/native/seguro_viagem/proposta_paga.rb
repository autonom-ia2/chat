# PROPOSTA JÁ PAGA (#3247): a conferência que `gerar_proposta_seguro_viagem` faz antes de comprar de novo.
#
# Proposta com `pago_em` é dinheiro recebido: gravar outra proposta na mesma cotação apagaria `pago_em`,
# `voucher_enviado_em`, `aviso_pago_em` e o carrinho pago, e o cliente compraria duas vezes. Vale também para outra
# cotação da MESMA viagem nesta conversa (o cliente "cota de novo" depois de pagar): as consultas de pagamento olham a
# proposta mais nova, e a nova esconderia a paga.
#
# MESMA VIAGEM = mesmos destinos, mesmas datas de ida e volta e mesma lista de idades, lidos do `pedido` que a cotação já
# guarda (`CotarSeguroViagem#guardar`). Sem CPF nem nome: a cotação não guarda dado pessoal.
module Autonomia::Agents::Tools::Native::SeguroViagem::PropostaPaga
  VIAGEM = %w[destinos data_saida data_retorno idades].freeze

  module_function

  def paga?(cotacao)
    cotacao.proposta.to_h['pago_em'].present?
  end

  # -> a cotação paga que impede a proposta nova: a própria, ou outra deste agente na conversa que é a mesma viagem. nil
  # quando nada impede.
  def impedindo(cotacao, agent)
    return cotacao if paga?(cotacao)

    outras = Autonomia::Agents::CotacaoDeViagem.where(conversation_id: cotacao.conversation_id, autonomia_agent_id: agent.id)
                                               .where.not(id: cotacao.id).where("proposta->>'pago_em' IS NOT NULL")
    outras.order(:id).find { |outra| mesma_viagem?(outra, cotacao) }
  end

  def mesma_viagem?(uma, outra)
    assinatura(uma) == assinatura(outra)
  end

  # Destinos e idades sem ordem: a lista é a mesma viagem ainda que o modelo a tenha escrito em outra ordem.
  def assinatura(cotacao)
    pedido = cotacao.pedido.to_h
    [pedido['destinos'].to_a.map(&:to_s).sort, pedido['data_saida'], pedido['data_retorno'], pedido['idades'].to_a.map(&:to_i).sort]
  end
end
