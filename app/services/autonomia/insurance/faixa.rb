# A FAIXA DE UMA COTAÇÃO: o que separa dois trabalhos de `cotar_seguro` que não se substituem na mesma conversa
# (`ToolRun#faixa`, índice único por conversa, ferramenta e faixa).
#
# Até a chat#608 era o produto (auto, residencial). Desde a chat#612 é o produto mais o BEM ("auto:nivus fvu2f42"),
# porque o cliente cota dois carros e dois apartamentos de uma vez. O nome do bem é do modelo (`item`, na ferramenta):
# é ele quem decide se o pedido é o mesmo bem (recotar, corrigir) ou outro. Aqui só se compõe e se lê a faixa, com
# métodos de string sobre o NOSSO identificador; nada daqui interpreta o que o cliente escreveu.
#
# As execuções de antes da chat#612 têm só o produto ("auto"), e continuam sendo lidas: o ramo de "auto" é "auto".
module Autonomia::Insurance::Faixa
  SEPARADOR = ':'.freeze
  # O nome do bem é curto; o teto só impede que um texto longo do modelo encha a coluna.
  MAX_ITEM = 80

  module_function

  # -> a faixa de uma cotação do `produto` para o bem `item`; só o produto quando o modelo não nomeou o bem.
  def de(produto, item)
    nome = item.to_s.squish.downcase[0, MAX_ITEM].presence
    nome ? "#{produto}#{SEPARADOR}#{nome}" : produto.to_s
  end

  # -> o ramo da faixa ("auto" de "auto:nivus fvu2f42", e de "auto").
  def ramo(faixa)
    faixa.to_s.split(SEPARADOR, 2).first.to_s
  end

  # -> a faixa tem nome de bem? As de antes da chat#612 têm só o ramo.
  def com_bem?(faixa)
    faixa.to_s.include?(SEPARADOR)
  end

  # -> a faixa é do ramo? (a do próprio ramo, sem bem, também é)
  def do_ramo?(faixa, ramo)
    ramo.present? && (faixa.to_s == ramo.to_s || faixa.to_s.start_with?("#{ramo}#{SEPARADOR}"))
  end

  # O NOME DO BEM É NOSSO (item 5A da auditoria de voz, 26/09/2026). O `item` continua sendo a chave da faixa, mas o
  # modelo o escreve curto e distintivo ("apto 302 ubatuba", "nivus fvu2f42"), e a Lia o copiava na fala: o aviso o
  # apresentava como o nome do bem. Agora ele aparece como identificador, e quem mostra a descrição ao modelo põe esta
  # frase depois dela, uma vez.
  NOME_NA_CONVERSA = 'O identificador é nosso: na conversa, chame esse bem como a pessoa chama.'.freeze

  # -> como a cotação aparece ao modelo (aviso, situação): o ramo e, havendo, o identificador do bem como o modelo o
  # escreveu e o que o parâmetro `produto` das leituras aceita ("auto, bem de identificador nivus (produto: auto:nivus)").
  def descricao(run)
    item = item(run)
    ramo = ramo(run.faixa).presence || 'auto'
    item ? "#{ramo}, bem de identificador #{item} (produto: #{run.faixa})" : ramo
  end

  # -> o nome que o modelo deu ao bem desta execução, ou nil nas de antes da chat#612.
  def item(run)
    run.arguments.to_h.stringify_keys['item'].to_s.squish.presence
  end
end
