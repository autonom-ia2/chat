# O CARRINHO ANTERIOR NÃO PAGO (#3263): o que `gerar_proposta_seguro_viagem` faz com o carrinho da proposta guardada
# antes de comprar outro na mesma cotação (dado corrigido, outro plano ou link vencido). Vale também para o carrinho de
# outra cotação da mesma viagem nesta conversa (#3266, `SeguroViagem::OutrasDaMesmaViagem`), com a mesma regra.
#
# POR QUÊ. O carrinho não pago já tem voucher "Ativo" na Universal, e ela recusa a compra nova do mesmo viajante para a
# mesma viagem ("já consta um voucher para essa viagem", produção, 26/11). O anterior precisa sair antes.
#
# A DECISÃO, pelo valor BRUTO do `statusPagamento` lido AGORA no `StatusPagamento`, comparado como texto exato. Aqui não
# vale a leitura larga de `Pagamento.situacao` (tudo que não é "Pago" nem "Cancelado" é aguardando): cancelar é
# irreversível, e só o vazio é o carrinho que ninguém começou a pagar.
#   - `""` (checkout aberto, sem forma de pagamento escolhida): cancela (`Universal::Cliente#cancelar`). Só a resposta
#     com `sucesso: true` libera a compra nova;
#   - `"Cancelado"` (sem diferença de maiúscula): nada a fazer, a compra nova segue;
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
# não volta atrás, e o link anterior morreu. A equipe recebe uma nota primeiro (`NotaNaHora` nunca levanta); na compra
# sem link, a nota cita o carrinho novo que ficou sem link. Depois, fora do lock da compra (a transação dela pode ter
# sido desfeita), a cotação guarda na proposta anterior `situacao: cancelado`, `cancelado_na_troca_em` e, sem link,
# `carrinho_sem_link`: a varredura não a confere mais, o lembrete se cala e a ferramenta não a devolve como guardada. A
# espera pelo lock estourada nessa gravação só vai ao log: quem tem o lock relê "Cancelado" e grava outra proposta. O
# modelo sabe que o link anterior não vale mais, antes do texto da falha.
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

  # -> o carrinho DESTA cotação que acabou de ser cancelado, ou nil (sem carrinho guardado, ou já cancelado na
  # Universal). Levanta `EmAberto` ou `NaoLiberado` quando a compra nova não pode sair.
  #
  # `outras` (#3266): as outras cotações da mesma viagem com carrinho em aberto (`OutrasDaMesmaViagem.com_carrinho`), com
  # a mesma regra. TODOS os status são lidos antes de qualquer cancelamento: um carrinho em aberto (ou a leitura que
  # falha) para tudo sem cancelar nenhum. Depois, as outras são canceladas primeiro e a desta cotação por último, e cada
  # outra cancelada vai a `cancelada` (um proc) como [cotação, carrinho], na hora: se um cancelamento seguinte falhar,
  # quem chamou ainda sabe o que já foi cancelado.
  def liberar!(cotacao, cliente, outras = [], cancelada = nil)
    pendentes = [*outras, cotacao].filter_map { |dona| pendente(dona, cliente) }
    cancelar_pendentes!(cotacao, cliente, pendentes, cancelada)
    pendentes.find { |dona, _carrinho| dona == cotacao }&.last
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

  # A compra nova não saiu depois de algum cancelamento nesta chamada (`SeguroViagem::CarrinhosAnteriores`): `texto` é o
  # que as falhas já devolveram; `compra`, a resposta da compra sem link, ou nil no erro; `carrinho`, o desta cotação que
  # foi cancelado, ou nil quando só o de outra cotação da mesma viagem foi (#3266; essa é marcada por
  # `OutrasDaMesmaViagem`). Avisa a equipe, marca a proposta desta cotação como cancelada e diz ao modelo que o link
  # anterior morreu.
  def compra_nao_saiu(cotacao, carrinho, texto, conversation:, compra: nil)
    sem_link = compra.is_a?(Hash) ? compra['codigoCarrinho'].presence : nil
    nota_do_cancelado(conversation, sem_link)
    marcar_cancelado(cotacao, carrinho, sem_link) if carrinho
    "#{TEXTO_CANCELADO_SEM_NOVA} #{texto}"
  end

  # -> [dona, carrinho] quando o carrinho da cotação `dona` precisa ser cancelado; nil sem carrinho ou já cancelado.
  # Levanta `EmAberto` quando ele não pode ser cancelado.
  def pendente(dona, cliente)
    carrinho = Pagamento.carrinho(dona)
    return if carrinho.blank?

    pagamento = pagamento_do(cliente.status_do_pagamento(carrinho))
    return if pagamento.is_a?(String) && pagamento.casecmp?(CANCELADO_NA_UNIVERSAL)
    raise EmAberto unless pagamento == SEM_PAGAMENTO

    [dona, carrinho]
  end

  # As outras primeiro, a desta cotação por último (é a última da lista).
  def cancelar_pendentes!(cotacao, cliente, pendentes, cancelada)
    pendentes.each do |dona, carrinho|
      cancelar!(dona, cliente, carrinho)
      cancelada&.call([dona, carrinho]) unless dona == cotacao
    end
  end

  # O `statusPagamento` como veio, ou nil quando o corpo não é objeto.
  def pagamento_do(status)
    status.is_a?(Hash) ? status['statusPagamento'] : nil
  end

  def cancelar!(dona, cliente, carrinho)
    resposta = cliente.cancelar(carrinho)
    raise NaoLiberado, Erro.new(Codigos::INDISPONIVEL) unless resposta.is_a?(Hash) && resposta['sucesso'] == true

    Rails.logger.info("[autonomia][seguro_viagem] carrinho_anterior_cancelado cotacao=#{dona.id}")
  end

  # Relendo sob o lock: só marca a proposta que ainda é a do carrinho cancelado. A espera pelo lock estourada (a mesma
  # lista da ferramenta) vai ao log e segue: o texto ao modelo e a nota já valem sem a marca.
  def marcar_cancelado(cotacao, carrinho, sem_link)
    cotacao.with_lock do
      proposta = cotacao.proposta.to_h
      if proposta['codigo_carrinho'] == carrinho
        marca = { 'situacao' => Pagamento::CANCELADO, 'cancelado_na_troca_em' => Time.current.iso8601 }
        cotacao.update!(proposta: proposta.merge(marca, sem_link ? { 'carrinho_sem_link' => sem_link } : {}))
      end
    end
  rescue *Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem::ESPERA_DO_LOCK
    Rails.logger.warn("[autonomia][seguro_viagem] carrinho_anterior_sem_marca cotacao=#{cotacao.id}")
  end

  # Na compra sem link, a nota cita o carrinho novo que ficou sem link (número da Universal, não é dado pessoal).
  def nota_do_cancelado(conversation, sem_link)
    texto = if sem_link
              I18n.t("#{Falhas::NOTAS}.anterior_cancelado_sem_link", carrinho: sem_link)
            else
              I18n.t("#{Falhas::NOTAS}.anterior_cancelado_sem_nova")
            end
    Autonomia::Insurance::NotaNaHora.postar(conversation, texto, chave: "universal:anterior_cancelado_sem_nova:#{conversation&.id}")
  end

  # Uma nota por conversa e caso, como as das falhas.
  def nota(conversation, caso)
    Autonomia::Insurance::NotaNaHora.postar(conversation, I18n.t("#{Falhas::NOTAS}.#{caso}"),
                                            chave: "universal:#{caso}:#{conversation&.id}")
  end

  private_class_method :pendente, :cancelar_pendentes!, :pagamento_do, :cancelar!, :marcar_cancelado, :nota_do_cancelado, :nota
end
