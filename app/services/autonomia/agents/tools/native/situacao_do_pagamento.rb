# SITUAÇÃO DO PAGAMENTO (#3246): a ferramenta do agente contratado "Seguro Viagem Universal" que confere na Universal
# se a proposta da conversa foi paga, quando o cliente diz que pagou ou pergunta se caiu.
#
# SEM PARÂMETRO. O carrinho é o da proposta guardada (`SeguroViagem::Pagamento`): nunca um número do modelo ou do
# cliente. Sem proposta na conversa, recusa sem chamar a Universal.
#
# PAGO E VOUCHER AINDA NÃO ENVIADO NESTA COTAÇÃO: marca o cartão do voucher (`SeguroViagem::EntregaDoVoucher`), que sai
# depois da resposta do turno, e devolve `voucher_vai_junto: true`. O automático é uma vez por cotação:
# `voucher_enviado_em` (gravado quando o PDF sai) segura a próxima conferência; o pedido de segunda via é a outra
# ferramenta. O primeiro "pago" visto grava `pago_em` na proposta (a data da Universal, ou a hora em que foi visto), sob
# o lock da cotação, como a proposta.
#
# ESCREVE (`escreve?` true): marca o cartão que manda o voucher ao cliente e grava `pago_em`. Nas rodadas das prontas,
# roda uma vez por turno (`UmaEscritaPorTurno`); a conferência que a Universal recusou não conta como feita.
#
# NUNCA LEVANTA com a seguradora fora: o erro do cliente HTTP passa por `SeguroViagem::Falhas` (`Pagamento.falha`: o
# pedido inválido vira indisponível, porque não há dado do cliente a corrigir).
class Autonomia::Agents::Tools::Native::SituacaoDoPagamento < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Pagamento = SeguroViagem::Pagamento

  TEXTO_SEM_PROPOSTA = 'Esta conversa ainda não tem proposta gerada, então não há pagamento para conferir. Se o cliente ' \
                       'pagou por outro caminho, passe a conversa para a equipe.'.freeze

  class << self
    include SeguroViagem::PortaDoContratado

    def escreve? = true

    def slug
      'situacao_do_pagamento'
    end

    def tool_name
      'Situação do pagamento do seguro viagem'
    end

    def description
      'Confere na seguradora se a proposta desta conversa foi paga. Use quando o cliente disser que pagou ou perguntar ' \
        'se o pagamento caiu. Devolve a situação (pago, aguardando ou cancelado), a data do pagamento quando houver e ' \
        'se o voucher em PDF vai junto com a sua resposta. Não tem parâmetro: o número é o da proposta desta conversa.'
    end
  end

  def call
    return error('pagamento_sem_conversa') if conversa.nil?

    cotacao = Pagamento.cotacao_com_proposta(conversa, agent)
    return recusar('sem_proposta', TEXTO_SEM_PROPOSTA) if cotacao.nil?

    conferir(cotacao)
  end

  private

  def conferir(cotacao)
    status = Pagamento.cliente(agent).status_do_pagamento(Pagamento.carrinho(cotacao))
    situacao = Pagamento.situacao(status)
    voucher = situacao == Pagamento::PAGO && voucher_do_pago(cotacao, status)
    JSON.generate({ situacao: situacao, data_do_pagamento: Pagamento.data(status), voucher_vai_junto: voucher })
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
    Pagamento.falha(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  # Grava `pago_em` (só a primeira vez) e marca o cartão quando o voucher ainda não saiu. -> o voucher vai junto?
  def voucher_do_pago(cotacao, status)
    enviado = nil
    cotacao.with_lock do
      proposta = cotacao.proposta.to_h
      enviado = proposta['voucher_enviado_em'].present?
      cotacao.update!(proposta: proposta.merge('pago_em' => Pagamento.pago_em(status))) if proposta['pago_em'].blank?
    end
    return false if enviado

    delivery.marcar_cartao(SeguroViagem::EntregaDoVoucher.cartao(cotacao))
    true
  end

  def conversa
    delivery.try(:conversation)
  end
end
