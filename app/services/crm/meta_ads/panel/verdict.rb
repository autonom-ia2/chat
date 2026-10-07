# Veredito de um anúncio, em palavras (#1088, F3a, CA-3.2). Pequeno negócio vende pouco por anúncio: com poucos
# dados, o veredito é "ainda é cedo", nunca aumentar ou pausar.
#
# - menos de MIN_CONVERSATIONS conversas → `early` (ainda é cedo);
# - sem venda depois disso → `review` (revisar o anúncio);
# - menos de MIN_SALES vendas → `signal` (sinal inicial);
# - com base suficiente, compara o custo por venda com a média da conta: até a média → `up` (aumentar);
#   REVIEW_FACTOR acima da média → `review`; entre os dois → `keep` (manter).
#
# `reason` (F3b) é o porquê do veredito na tela do anúncio, com o número que o sustenta. Sai da mesma regra, para
# o porquê nunca contradizer o veredito.
module Crm::MetaAds::Panel::Verdict
  MIN_CONVERSATIONS = 20
  MIN_SALES = 3
  REVIEW_FACTOR = 1.3
  COMPARED = { 'up' => 'below_average', 'keep' => 'near_average', 'review' => 'above_average' }.freeze

  module_function

  def for(conversations:, sales:, cost_per_sale:, average_cost_per_sale:)
    return 'early' if conversations < MIN_CONVERSATIONS
    return 'review' if sales.zero?
    return 'signal' if sales < MIN_SALES || average_cost_per_sale.nil?
    return 'up' if cost_per_sale <= average_cost_per_sale
    return 'review' if cost_per_sale >= average_cost_per_sale * REVIEW_FACTOR

    'keep'
  end

  # row: a linha do anúncio no Panel::Report (conversations, sales, cost_per_sale, verdict).
  def reason(row, average_cost_per_sale:)
    blank = { missing_conversations: nil, difference: nil }
    return blank.merge(kind: 'early', missing_conversations: MIN_CONVERSATIONS - row[:conversations]) if row[:verdict] == 'early'
    return blank.merge(kind: 'no_sales') if row[:sales].zero?
    return blank.merge(kind: 'signal') if row[:verdict] == 'signal'

    blank.merge(kind: COMPARED.fetch(row[:verdict]), difference: (row[:cost_per_sale] - average_cost_per_sale).abs.round(2))
  end
end
