# O CARRINHO ANTERIOR NÃO PAGO (#3263): o que `gerar_proposta_seguro_viagem` faz com o carrinho da proposta guardada
# antes de comprar outro na mesma cotação (dado corrigido, outro plano ou link vencido).
#
# POR QUÊ. O carrinho não pago já tem voucher "Ativo" na Universal, e ela recusa a compra nova do mesmo viajante para a
# mesma viagem ("já consta um voucher para essa viagem", produção, 26/11). O anterior precisa sair antes.
#
# A DECISÃO, pela situação do `StatusPagamento` lida AGORA, com a mesma leitura de `situacao_do_pagamento`
# (`SeguroViagem::Pagamento.situacao`):
#   - cancelado: nada a fazer, a compra nova segue;
#   - aguardando: cancela (`Universal::Cliente#cancelar`). Só a resposta com `sucesso: true` libera a compra nova;
#   - pago (o `pago_em` ainda não gravado; gravado, a `PropostaPaga` já recusou antes) ou situação que não veio legível
#     (corpo que não é objeto, sem `statusPagamento`): nem cancela nem compra (`EmAberto`).
# O erro da Universal na leitura ou no cancelamento, e o cancelamento sem `sucesso: true`, também param a compra
# (`NaoLiberado`, com o erro para `SeguroViagem::Falhas`).
#
# A RECUSA (`tratar`), como `SeguroViagem::Falhas`: o `EmAberto` registra `pagamento_do_anterior_em_aberto` e manda o
# modelo conferir o pagamento; o `NaoLiberado` passa pelas falhas como consulta sem dado do cliente (o pedido inválido
# vira indisponível, como em `situacao_do_pagamento`). Nos dois, nada foi comprado.
#
# Roda sob o lock da cotação, como a compra. Não grava nada: a proposta nova sobrescreve a anterior, como sempre, e a
# conferência automática do pagamento larga o carrinho anterior (`proposta_trocada`). Log só com o id da cotação.
module Autonomia::Agents::Tools::Native::SeguroViagem::CarrinhoAnterior
  Pagamento = Autonomia::Agents::Tools::Native::SeguroViagem::Pagamento
  Erro = Autonomia::Seguradoras::Universal::Cliente::Erro
  Codigos = Autonomia::Seguradoras::Universal::Codigos

  TEXTO_EM_ABERTO = 'A proposta anterior desta conversa pode já ter sido paga, então não cancelei o link dela nem gerei ' \
                    'outra. Confira o pagamento com situacao_do_pagamento antes de qualquer coisa.'.freeze

  # O anterior pode estar pago, ou a situação dele não veio legível.
  class EmAberto < StandardError; end

  # A Universal não deixou ler a situação ou não confirmou o cancelamento. `erro` é o `Universal::Cliente::Erro`.
  class NaoLiberado < StandardError
    attr_reader :erro

    def initialize(erro)
      super(erro.codigo)
      @erro = erro
    end
  end

  # O que `liberar!` levanta quando a compra nova não pode sair.
  NAO_SAIU = [EmAberto, NaoLiberado].freeze

  module_function

  # Levanta `EmAberto` ou `NaoLiberado` quando a compra nova não pode sair. Sem carrinho guardado, nada a fazer.
  def liberar!(cotacao, cliente)
    carrinho = Pagamento.carrinho(cotacao)
    return if carrinho.blank?

    case situacao(cliente.status_do_pagamento(carrinho))
    when Pagamento::CANCELADO then nil
    when Pagamento::AGUARDANDO then cancelar!(cotacao, cliente, carrinho)
    else raise EmAberto
    end
  rescue Erro => e
    raise NaoLiberado, e
  end

  # -> o texto que o modelo lê, com a recusa registrada. `motivo` é o que `liberar!` levantou; `acao`, o slug da
  # ferramenta.
  def tratar(motivo, acao:, agent:, conversation:)
    if motivo.is_a?(NaoLiberado)
      return Autonomia::Agents::Tools::Native::SeguroViagem::Falhas
             .tratar_sem_dado_do_cliente(motivo.erro, acao: acao, agent: agent, conversation: conversation)
    end

    Autonomia::Agents::Tools::Recusa.registrar('pagamento_do_anterior_em_aberto', slug: acao, agente: agent,
                                                                                  conversa: conversation&.id)
    TEXTO_EM_ABERTO
  end

  # -> a situação, ou nil quando o corpo não diz nada (não é objeto, ou não tem `statusPagamento`). O vazio que a
  # Universal devolve no carrinho ainda sem forma de pagamento é legível: é aguardando.
  def situacao(status)
    return nil unless status.is_a?(Hash) && status.key?('statusPagamento')

    Pagamento.situacao(status)
  end

  def cancelar!(cotacao, cliente, carrinho)
    resposta = cliente.cancelar(carrinho)
    raise NaoLiberado, Erro.new(Codigos::INDISPONIVEL) unless resposta.is_a?(Hash) && resposta['sucesso'] == true

    Rails.logger.info("[autonomia][seguro_viagem] carrinho_anterior_cancelado cotacao=#{cotacao.id}")
  end

  private_class_method :situacao, :cancelar!
end
