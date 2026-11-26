# O CARRINHO ANTERIOR NÃO PAGO (#3263): o que `gerar_proposta_seguro_viagem` faz com o carrinho da proposta guardada
# antes de comprar outro na mesma cotação (dado corrigido, outro plano ou link vencido).
#
# POR QUÊ. O carrinho não pago já tem voucher "Ativo" na Universal, e ela recusa a compra nova do mesmo viajante para a
# mesma viagem ("já consta um voucher para essa viagem", produção, 26/11). O anterior precisa sair antes.
#
# A DECISÃO, pelo valor BRUTO do `statusPagamento` lido AGORA no `StatusPagamento`, comparado como texto exato. Aqui não
# vale a leitura larga de `Pagamento.situacao` (tudo que não é "Pago" nem "Cancelado" é aguardando): cancelar é
# irreversível, e só o vazio é o carrinho que ninguém começou a pagar.
#   - `""` (checkout aberto, sem forma de pagamento escolhida): cancela (`Universal::Cliente#cancelar`). Só a resposta
#     com `sucesso: true` libera a compra nova;
#   - `"Cancelado"`: nada a fazer, a compra nova segue;
#   - qualquer outro valor ("Pago" ainda sem `pago_em`, "Aguardando Pagamento", um valor novo, a chave ausente, o corpo
#     que não é objeto): nem cancela nem compra (`EmAberto`).
# O erro da Universal na leitura ou no cancelamento, e o cancelamento sem `sucesso: true`, também param a compra
# (`NaoLiberado`, com o erro para `SeguroViagem::Falhas`).
#
# A RECUSA (`tratar`), como `SeguroViagem::Falhas`: o `EmAberto` registra `pagamento_do_anterior_em_aberto`, deixa uma
# nota privada para a equipe e manda o modelo conferir o pagamento; o `NaoLiberado` passa pelas falhas como consulta sem
# dado do cliente (o pedido inválido vira indisponível, como em `situacao_do_pagamento`). Nos dois, nada foi comprado.
#
# CANCELOU E A COMPRA NOVA NÃO SAIU (`compra_nao_saiu`): erro da Universal na compra, ou compra sem link. O cancelamento
# não volta atrás, e o link anterior morreu. Fora do lock da compra (a transação dela pode ter sido desfeita), a cotação
# guarda `situacao: cancelado` e `cancelado_na_troca_em` na proposta anterior: a varredura não a confere mais, o
# lembrete se cala e a ferramenta não a devolve como guardada. A equipe recebe uma nota e o modelo sabe que o link
# anterior não vale mais, antes do texto da falha.
#
# Roda sob o lock da cotação, como a compra. Sem a falha acima, não grava nada: a proposta nova sobrescreve a anterior,
# como sempre, e a conferência automática do pagamento larga o carrinho anterior (`proposta_trocada`). Log e nota só
# com ids: nada do carrinho nem do cliente.
module Autonomia::Agents::Tools::Native::SeguroViagem::CarrinhoAnterior
  Pagamento = Autonomia::Agents::Tools::Native::SeguroViagem::Pagamento
  Falhas = Autonomia::Agents::Tools::Native::SeguroViagem::Falhas
  Erro = Autonomia::Seguradoras::Universal::Cliente::Erro
  Codigos = Autonomia::Seguradoras::Universal::Codigos

  # O `statusPagamento` do carrinho que ninguém começou a pagar, e o do carrinho já cancelado.
  SEM_PAGAMENTO = ''.freeze
  CANCELADO_NA_UNIVERSAL = 'Cancelado'.freeze

  TEXTO_EM_ABERTO = 'A proposta anterior desta conversa pode já ter sido paga, então não cancelei o link dela nem gerei ' \
                    'outra. Confira o pagamento com situacao_do_pagamento antes de qualquer coisa.'.freeze
  TEXTO_CANCELADO_SEM_NOVA = 'O link de pagamento anterior foi cancelado e não vale mais, e a proposta nova não saiu: ' \
                             'não mande o link anterior.'.freeze

  # O anterior pode estar pago ou em pagamento, ou a situação dele não veio legível.
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

  # -> o carrinho que acabou de ser cancelado, ou nil (sem carrinho guardado, ou já cancelado na Universal). Levanta
  # `EmAberto` ou `NaoLiberado` quando a compra nova não pode sair.
  def liberar!(cotacao, cliente)
    carrinho = Pagamento.carrinho(cotacao)
    return if carrinho.blank?

    case pagamento_do(cliente.status_do_pagamento(carrinho))
    when CANCELADO_NA_UNIVERSAL then nil
    when SEM_PAGAMENTO then cancelar!(cotacao, cliente, carrinho)
    else raise EmAberto
    end
  rescue Erro => e
    raise NaoLiberado, e
  end

  # -> o texto que o modelo lê, com a recusa registrada. `motivo` é o que `liberar!` levantou; `acao`, o slug da
  # ferramenta.
  def tratar(motivo, acao:, agent:, conversation:)
    return Falhas.tratar_sem_dado_do_cliente(motivo.erro, acao: acao, agent: agent, conversation: conversation) if motivo.is_a?(NaoLiberado)

    Autonomia::Agents::Tools::Recusa.registrar('pagamento_do_anterior_em_aberto', slug: acao, agente: agent,
                                                                                  conversa: conversation&.id)
    nota(conversation, 'anterior_em_aberto')
    TEXTO_EM_ABERTO
  end

  # A compra nova não saiu (`texto` é o que as falhas já devolveram). Sem carrinho cancelado nesta chamada, o texto como
  # veio. Com ele: marca a proposta anterior como cancelada, avisa a equipe e diz ao modelo que o link anterior morreu.
  def compra_nao_saiu(cotacao, carrinho, texto, conversation:)
    return texto if carrinho.nil?

    marcar_cancelado(cotacao, carrinho)
    nota(conversation, 'anterior_cancelado_sem_nova')
    "#{TEXTO_CANCELADO_SEM_NOVA} #{texto}"
  end

  # O `statusPagamento` como veio, ou nil quando o corpo não é objeto.
  def pagamento_do(status)
    status.is_a?(Hash) ? status['statusPagamento'] : nil
  end

  def cancelar!(cotacao, cliente, carrinho)
    resposta = cliente.cancelar(carrinho)
    raise NaoLiberado, Erro.new(Codigos::INDISPONIVEL) unless resposta.is_a?(Hash) && resposta['sucesso'] == true

    Rails.logger.info("[autonomia][seguro_viagem] carrinho_anterior_cancelado cotacao=#{cotacao.id}")
    carrinho
  end

  # Relendo sob o lock: só marca a proposta que ainda é a do carrinho cancelado.
  def marcar_cancelado(cotacao, carrinho)
    cotacao.with_lock do
      proposta = cotacao.proposta.to_h
      if proposta['codigo_carrinho'] == carrinho
        cotacao.update!(proposta: proposta.merge('situacao' => Pagamento::CANCELADO,
                                                 'cancelado_na_troca_em' => Time.current.iso8601))
      end
    end
  end

  # Uma nota por conversa e caso, como as das falhas.
  def nota(conversation, caso)
    Autonomia::Insurance::NotaNaHora.postar(conversation, I18n.t("#{Falhas::NOTAS}.#{caso}"),
                                            chave: "universal:#{caso}:#{conversation&.id}")
  end

  private_class_method :pagamento_do, :cancelar!, :marcar_cancelado, :nota
end
