# O ponto ÚNICO de onde CRM › Números › "De onde vieram os clientes" (#2001, F6 do #1871) tira os cards: a tela, o
# relatório baixado e o "Ver" da Lista (Crm::Cards::FilterQuery, `entrou_em`) passam todos por aqui. Assim o número da
# tela, o do arquivo e o tamanho da lista nunca divergem, e um filtro novo de contato (por exemplo, o contato marcado
# como "fora dos números", #2084/#2085) entra numa linha só, neste método.
#
# Entra no mês quem entrou no funil no mês (card criado) ou foi ganho no mês (decisão 1 do Rodrigo, 25/10: a venda
# conta no mês em que fechou). `range` é inclusivo, no fuso da conta (Crm::Numeros::Mes#range).
module Crm::Numeros::Origens::Cards
  ENTROU_OU_VENDEU = <<~SQL.squish.freeze
    (crm_cards.created_at BETWEEN :inicio AND :fim)
    OR (crm_cards.status = :ganho AND crm_cards.closed_at BETWEEN :inicio AND :fim)
  SQL

  module_function

  def do_mes(cards, range)
    cards.where(ENTROU_OU_VENDEU, inicio: range.begin, fim: range.end, ganho: Crm::Card.statuses[:won])
  end
end
