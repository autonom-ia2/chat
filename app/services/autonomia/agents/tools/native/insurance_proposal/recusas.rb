# O QUE A PROPOSTA INDIVIDUAL DIZ QUANDO RECUSA — textos e a forma da recusa (entrega 8).
#
# Separado do comportamento pelo mesmo motivo de `InsuranceQuote::Recusas`: os textos mudam quando
# o vocabulário muda; `start` e `poll` mudam quando o fluxo muda.
#
# UM TEXTO POR MOTIVO, lido nos DOIS lugares: pelo MODELO na conferência do turno (`precheck`, que
# devolve uma `Conferencia`) e pelo CLIENTE no envio (`start`, cuja recusa vira entrega; `poll`,
# quando a cotação de origem morreu no meio). Por isso cada frase é escrita para uma pessoa ler —
# sem código, sem nome de campo, sem vocabulário de sistema — e diz o que fazer em seguida: o modelo
# a parafraseia, o cliente a lê como está.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Recusas
  extend ActiveSupport::Concern

  SEM_SEGURADORA = 'Para gerar a proposta, preciso saber de qual seguradora você quer — o nome como ' \
                   'apareceu na lista de preços.'.freeze
  ACIMA_DO_TETO = 'Consigo gerar a proposta de até duas seguradoras por vez. Me diga quais duas você ' \
                  'quer primeiro.'.freeze
  SEM_COTACAO = 'Não encontrei nesta conversa uma cotação com preços para gerar a proposta. Se ' \
                'quiser, faço a cotação primeiro.'.freeze
  # A COTAÇÃO DE ORIGEM DEIXOU DE SER A ÚLTIMA DA CONVERSA (P1 do Codex; regra única desde a rodada
  # 4): o cliente mandou refazer depois deste pedido, e a proposta sairia dos preços que ele
  # descartou — o risco errado com cara de certo. Um texto só, porque é um motivo só: não importa se
  # a cotação nova ainda está buscando preço, se já entregou ou se morreu pelo caminho; a lista que
  # vale é a dela. O que o cliente precisa saber é que a proposta espera pelos preços novos.
  SUBSTITUIDA = 'A cotação foi refeita depois desse pedido, e a proposta sairia dos preços antigos. ' \
                'Quando os preços novos chegarem, é só me pedir de novo.'.freeze
  # A RECOTAÇÃO MORREU SEM PREÇO (rodada 5, achado do verificador cego). O MOTIVO é o mesmo da
  # anterior — a origem não é mais a última —, mas o que o cliente PODE FAZER é outro: não há preço
  # novo a caminho, e esperar por ele é esperar para sempre. A regra não mudou (ver
  # `Origem#recotacao_sem_preco?`); mudou a frase, e ela oferece o único caminho que existe.
  RECOTACAO_SEM_PRECO = 'A cotação foi refeita depois desse pedido, mas a nova não chegou a trazer ' \
                        'preços — então não tenho de onde tirar a proposta. Se quiser, faço a ' \
                        'cotação de novo.'.freeze
  # SEM A COTAÇÃO DE ORIGEM NOS ARGUMENTOS (rodada 3, M4 do verificador cego): a execução foi aberta
  # antes do deploy que passou a fixá-la no aceite. Escolher uma cotação agora, minutos depois, é o
  # que a rodada 2 proibiu — então a resposta é honesta sobre o que aconteceu (não achei a cotação
  # DESTE pedido) e pede o pedido de novo, que já nasce com a origem fixada. Some sozinha: nenhuma
  # execução nova é aberta sem origem, e as `pending` de antes do deploy têm prazo de uma hora.
  SEM_ORIGEM = 'Não consegui localizar a cotação desta conversa para gerar a proposta. Me peça de ' \
               'novo, por favor, que eu busco o arquivo.'.freeze
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
  # silêncio. "Não tenho preço de" vale para um nome e para dois. Só sai do NOSSO mapa: o portal
  # dizendo 422 para quem está no mapa não é "não cotou", é `nao_gerada` (verificador cego, B1).
  def nao_cotou(falados)
    "Não tenho preço de #{falados.to_sentence(**LISTA)} nesta cotação. Quem cotou: " \
      "#{cotaram.to_sentence(**LISTA)}. Quer a proposta de alguma delas?"
  end

  # O PORTAL NÃO GEROU a proposta de quem cotou, e NENHUMA outra saiu: recusou o código que ele
  # próprio devolveu na cotação (422), ou falhou nas tentativas que tinha. O cliente lê que não saiu
  # e o que pode fazer; nunca "não cotou" — ele acabou de ler o preço dela.
  def nao_gerada(nomes)
    "Não consegui gerar a proposta de #{nomes.to_sentence(**LISTA)} agora. Posso tentar de novo daqui a " \
      'pouco, ou um atendente retoma daqui.'
  end

  # A mesma falha quando OUTRA proposta saiu: o aviso vem depois dos arquivos.
  def nao_saiu(nomes)
    "Não consegui gerar a proposta de #{nomes.to_sentence(**LISTA)} agora; as demais estão aqui em cima."
  end

  # A PROPOSTA QUE O PORTAL GEROU E NÃO COUBE NA PASSADA DO ENCERRAMENTO (rodada 5). Um arquivo por
  # passada é trade-off medido — dois downloads de 20 s não cabem nos 25 s que o Sidekiq dá ao job num
  # shutdown —, e o descarte continua; o que não pode é o cliente ler "não consegui gerar todas" sobre
  # um arquivo que EXISTE. Ele fica sabendo que ela está pronta e o que fazer: pedir de novo funciona,
  # porque a origem continua sendo a última cotação da conversa.
  def nao_enviada(nomes)
    "A proposta de #{nomes.to_sentence(**LISTA)} ficou pronta, mas não deu tempo de enviar o arquivo aqui. " \
      'Me peça de novo que eu mando.'
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
