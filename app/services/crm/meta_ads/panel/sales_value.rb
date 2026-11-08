# Valores de venda em R$ nos Anúncios (#2075, lote 13): seguem o Crm::ValorDeVenda. Sem `sales_value_view`, o dinheiro
# que sai do valor dos cards (vendido, em negociação, retorno por real investido) vem nil, com `value_hidden: true`
# para a tela saber que é falta de permissão e não falta de venda. O gasto e o que sai dele (custo por venda e por
# conversa, veredito) e as contagens ficam com quem já vê o painel. O card de que a pessoa é dona mostra o valor.
#
# `visible` é o Crm::MetaAds::VisibleConversations da pessoa do pedido; nil é quem trabalha pela conta, sem pessoa (o
# consultor, o resumo no WhatsApp, o alerta de gasto), que vê tudo.
module Crm::MetaAds::Panel::SalesValue
  KEYS = %i[sales_value open_value return_per_real].freeze

  module_function

  def visible?(visible)
    visible.nil? || visible.sales_values?
  end

  def card?(visible, card)
    visible.nil? || visible.card_value?(card)
  end

  # Os totais ou a linha de um anúncio sem o dinheiro. Só as chaves que a linha tem (o anúncio que não traz conversa
  # não tem valor nenhum e continua sem).
  def hide(row)
    row.merge(row.slice(*KEYS).transform_values { nil }, value_hidden: true)
  end
end
