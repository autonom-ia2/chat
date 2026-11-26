# O PAGAMENTO DA PROPOSTA do Seguro Viagem (#3246): o que `situacao_do_pagamento` e `segunda_via_do_voucher` dividem.
#
# O CARRINHO É SEMPRE O NOSSO. A cotação é a última DESTE agente na conversa que tem proposta guardada, e o carrinho é o
# `codigo_carrinho` que a compra devolveu (`GerarPropostaSeguroViagem#proposta_da`). Nunca um número vindo do modelo ou
# do cliente: as duas ferramentas não têm parâmetro. A última COM proposta, e não a última de todas: o cliente que pagou
# e depois pediu outra cotação (outra viagem, outra data) continua perguntando do pagamento que fez.
#
# A SITUAÇÃO vem do `statusPagamento` da Universal: "Pago" é pago; "Cancelado" é cancelado; o resto ("Aguardando
# Pagamento", o vazio do checkout ainda sem forma escolhida, ou um valor novo) é aguardando. Só "Pago" libera o voucher:
# o voucher nasce "Ativo" antes do pagamento, e o PDF só sai depois dele.
module Autonomia::Agents::Tools::Native::SeguroViagem::Pagamento
  PAGO = 'pago'.freeze
  AGUARDANDO = 'aguardando'.freeze
  CANCELADO = 'cancelado'.freeze
  DA_UNIVERSAL = { 'pago' => PAGO, 'cancelado' => CANCELADO }.freeze

  module_function

  # -> a cotação com a proposta, ou nil quando a conversa não tem proposta deste agente.
  def cotacao_com_proposta(conversation, agent)
    cotacao = Autonomia::Agents::CotacaoDeViagem.where(conversation_id: conversation.id, autonomia_agent_id: agent.id)
                                                .where.not(proposta: nil).order(:id).last
    carrinho(cotacao).present? ? cotacao : nil
  end

  def carrinho(cotacao)
    cotacao&.proposta.to_h['codigo_carrinho']
  end

  def cliente(agent)
    acesso = agent.acesso_da_seguradora
    Autonomia::Seguradoras::Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end

  # `status`: o corpo do `StatusPagamento`.
  def situacao(status)
    DA_UNIVERSAL.fetch(corpo(status)['statusPagamento'].to_s.strip.downcase, AGUARDANDO)
  end

  # -> a data do pagamento em dd/mm/aaaa, como a Universal a escreve (sem fuso, com ou sem fração), ou nil.
  def data(status)
    texto = corpo(status)['dataPagamento'].to_s
    return if texto.empty?

    DateTime.iso8601(texto).strftime('%d/%m/%Y')
  rescue Date::Error
    nil
  end

  def corpo(status)
    status.is_a?(Hash) ? status : {}
  end
end
