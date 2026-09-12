# O QUE A PROPOSTA INDIVIDUAL DIZ QUANDO RECUSA — textos e a forma da recusa (entrega 8).
#
# Separado do comportamento pelo mesmo motivo de `InsuranceQuote::Recusas`: os textos mudam quando
# o vocabulário muda; `start` e `poll` mudam quando o fluxo muda.
#
# UM TEXTO POR MOTIVO, lido nos DOIS lugares: pelo MODELO na conferência do turno (`precheck`, que
# devolve uma `Conferencia`) e pelo CLIENTE no envio (`start`, cuja recusa vira entrega). Por isso
# cada frase é escrita para uma pessoa ler — sem código, sem nome de campo, sem vocabulário de
# sistema — e diz o que fazer em seguida: o modelo a parafraseia, o cliente a lê como está.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Recusas
  extend ActiveSupport::Concern

  SEM_SEGURADORA = 'Para gerar a proposta, preciso saber de qual seguradora você quer — o nome como ' \
                   'apareceu na lista de preços.'.freeze
  ACIMA_DO_TETO = 'Consigo gerar a proposta de até duas seguradoras por vez. Me diga quais duas você ' \
                  'quer primeiro.'.freeze
  SEM_COTACAO = 'Não encontrei nesta conversa uma cotação com preços para gerar a proposta. Se ' \
                'quiser, faço a cotação primeiro.'.freeze
  LISTA = { two_words_connector: ' e ', last_word_connector: ' e ' }.freeze
  OU = { two_words_connector: ' ou ', last_word_connector: ' ou ' }.freeze

  private

  # "Bp pode ser Bp ou Bp Assinatura" — as candidatas são os nomes do PORTAL, os mesmos que o
  # cliente leu na lista de preços; o nome falado é o dele, devolvido a ele.
  def ambigua(escolha)
    partes = escolha.ambiguas.map { |falado, candidatas| "#{falado} pode ser #{candidatas.to_sentence(**OU)}" }
    "Tenho mais de uma opção com esse nome: #{partes.join('; ')}. Qual delas você quer?"
  end

  # TERMO 3: quem não cotou é dito, e quem cotou é listado — em vez do comparativo de todas em
  # silêncio. "Não tenho preço de" vale para um nome e para dois.
  def nao_cotou(falados)
    "Não tenho preço de #{falados.to_sentence(**LISTA)} nesta cotação. Quem cotou: " \
      "#{cotaram.to_sentence(**LISTA)}. Quer a proposta de alguma delas?"
  end

  # O portal disse que a seguradora não cotou, contra o nosso registro de que cotou. O cliente lê a
  # mesma coisa de sempre — quem cotou —, e a divergência vai ao log.
  def nao_saiu(nomes)
    "Não consegui gerar a proposta de #{nomes.to_sentence(**LISTA)} agora; as demais estão aqui em cima."
  end

  # A recusa do envio VIRA ENTREGA, e não falha — o contrato que `poll` reconhece pelo `pedido`, o
  # mesmo da cotação. Quem registra (conversa, agente, motivo) é o `AsyncRunJob`; `faltando` são só
  # NOMES de parâmetro, nunca valores.
  def recusa(motivo, texto, faltando:)
    { 'pedido' => texto, 'motivo' => motivo, 'faltando' => faltando }
  end

  # A recusa da conferência: o mesmo texto, na forma que o `Bound` registra e devolve ao modelo.
  def conferencia(motivo, texto, faltando)
    ::Autonomia::Agents::Tools::Native::Conferencia.new(texto: texto, faltando: faltando, motivo: motivo)
  end
end
