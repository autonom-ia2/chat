# O ponto ÚNICO de onde CRM › Números › "De onde vieram os clientes" (#2001, F6 do #1871) tira os cards: a tela, o
# relatório baixado e o "Ver" da Lista (Crm::Cards::FilterQuery, `entrou_em`) passam todos por aqui. Assim o número da
# tela, o do arquivo e o tamanho da lista nunca divergem.
#
# Contato marcado como parceiro do mercado ou "não é negócio" (#2084/#2085, flag contato_relacao) sai daqui pela regra
# única da Saúde (Crm::Relacao.cards_do_funil), por cima do escopo que chega (funis da pessoa ou policy_scope da Lista),
# nunca no lugar dele. Card sem contato continua contando.
#
# Entra no mês quem entrou no funil no mês (card criado) ou foi ganho no mês (decisão 1 do Rodrigo, 25/10: a venda
# conta no mês em que fechou). `range` é inclusivo, no fuso da conta (Crm::Numeros::Mes#range).
module Crm::Numeros::Origens::Cards
  ENTROU_OU_VENDEU = <<~SQL.squish.freeze
    (crm_cards.created_at BETWEEN :inicio AND :fim)
    OR (crm_cards.status = :ganho AND crm_cards.closed_at BETWEEN :inicio AND :fim)
  SQL

  module_function

  def do_mes(cards, range, account:)
    cards.merge(Crm::Relacao.cards_do_funil(account))
         .where(ENTROU_OU_VENDEU, inicio: range.begin, fim: range.end, ganho: Crm::Card.statuses[:won])
  end
end
