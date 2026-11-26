# SEGUNDA VIA DO VOUCHER (#3246): a ferramenta do agente contratado "Seguro Viagem Universal" que manda de novo o
# voucher em PDF quando o cliente pede (perdeu, não achou no e-mail, quer na conversa).
#
# SEM PARÂMETRO, com o carrinho da proposta guardada (`SeguroViagem::Pagamento`), como `situacao_do_pagamento`. Confere
# o pagamento na Universal antes: só com "Pago" marca o cartão do voucher (`SeguroViagem::EntregaDoVoucher`), mesmo que
# ele já tenha saído antes; aguardando ou cancelado recusa com o motivo, e nada sai.
#
# ESCREVE (`escreve?` true): manda um arquivo ao cliente.
#
# NUNCA LEVANTA com a seguradora fora: o erro do cliente HTTP passa por `SeguroViagem::Falhas` (`Pagamento.falha`: o
# pedido inválido vira indisponível, porque não há dado do cliente a corrigir).
class Autonomia::Agents::Tools::Native::SegundaViaDoVoucher < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Pagamento = SeguroViagem::Pagamento

  TEXTO_SEM_PROPOSTA = 'Esta conversa ainda não tem proposta gerada, então não há voucher para mandar. Se o cliente ' \
                       'comprou por outro caminho, passe a conversa para a equipe.'.freeze
  TEXTO_PENDENTE = 'O pagamento desta proposta ainda não aparece como feito, então o voucher ainda não existe. Pix pode ' \
                   'levar alguns minutos para aparecer; não prometa prazo.'.freeze
  TEXTO_CANCELADO = 'O pagamento desta proposta aparece como cancelado na seguradora, então não há voucher. Se o ' \
                    'cliente ainda quer o seguro, gere uma proposta nova.'.freeze

  class << self
    include SeguroViagem::PortaDoContratado

    def escreve? = true

    def slug
      'segunda_via_do_voucher'
    end

    def tool_name
      'Segunda via do voucher do seguro viagem'
    end

    def description
      'Manda de novo o voucher em PDF da proposta desta conversa, junto com a sua resposta, quando o cliente pedir. ' \
        'Confere o pagamento antes: sem pagamento feito, não há voucher. Não tem parâmetro: o número é o da proposta ' \
        'desta conversa.'
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
    situacao = Pagamento.situacao(Pagamento.cliente(agent).status_do_pagamento(Pagamento.carrinho(cotacao)))
    return recusar('pagamento_cancelado', TEXTO_CANCELADO) if situacao == Pagamento::CANCELADO
    return recusar('pagamento_pendente', TEXTO_PENDENTE) unless situacao == Pagamento::PAGO

    SeguroViagem::EntregaDoVoucher.marcar(delivery, cotacao)
    JSON.generate({ voucher_vai_junto: true })
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
    Pagamento.falha(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  def conversa
    delivery.try(:conversation)
  end
end
