# A resposta de "Quais destes querem dizer cliente?" na conferência de "Trazer minha lista" (#2896), como a tela a manda:
# `{ modo: 'preenchidas' }` (toda linha com algo escrito na coluna) ou `{ modo: 'valores', chaves: [...] }` (as chaves
# dos valores que a pessoa marcou). A tela nunca manda o texto do valor, e só o modo e as chaves são guardados.
#
# - `conhecida?`: o modo existe e, no modo `valores`, veio pelo menos uma chave;
# - `erro`: a pergunta tem de existir (uma coluna diz quem é cliente e a resposta não é "sim, todas") e, no modo
#   `valores`, toda chave tem de ser de um valor que a tela mostrou para ESSA coluna
#   (ContactImports::Trazer::ValoresDeCliente). A chave é da importação e da coluna, então a de outra coluna ou de
#   outra planilha é recusada. No pedido que troca a coluna, nenhuma chave vale: a pessoa ainda não viu os valores da
#   coluna nova.
class Relacionamentos::Trazer::EscolhaDosValores
  VALORES = ContactImports::Trazer::Cliente::VALORES

  # pedido: { 'modo' => 'valores', 'chaves' => ['9f2c…'] }
  def initialize(importacao, pedido)
    @importacao = importacao
    @modo = pedido['modo'].to_s
    @chaves = Array(pedido['chaves']).map(&:to_s).uniq
  end

  def conhecida?
    ContactImports::Trazer::Cliente::MODOS.include?(@modo) && (@modo != VALORES || @chaves.any?)
  end

  # coluna: o índice da coluna que diz quem é cliente como o pedido a deixa, ou nil quando a pergunta não existe.
  def erro(coluna)
    return 'pergunta_desconhecida' if coluna.nil?

    'resposta_desconhecida' if @modo == VALORES && !ContactImports::Trazer::ValoresDeCliente.new(@importacao).tem?(coluna, @chaves)
  end

  def para_guardar
    @modo == VALORES ? { 'modo' => @modo, 'chaves' => @chaves } : { 'modo' => @modo }
  end
end
