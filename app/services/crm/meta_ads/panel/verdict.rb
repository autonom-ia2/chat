# Veredito de um anúncio, em palavras (#1088, F3a, CA-3.2). Pequeno negócio vende pouco por anúncio: com poucos
# dados, o veredito é "ainda é cedo", nunca aumentar ou pausar.
#
# - menos de MIN_CONVERSATIONS conversas → `early` (ainda é cedo);
# - sem venda depois disso → `review` (revisar o anúncio);
# - menos de MIN_SALES vendas → `signal` (sinal inicial);
# - com base suficiente, compara o custo por venda com a média da conta: até a média → `up` (aumentar);
#   REVIEW_FACTOR acima da média → `review`; entre os dois → `keep` (manter).
module Crm::MetaAds::Panel::Verdict
  MIN_CONVERSATIONS = 20
  MIN_SALES = 3
  REVIEW_FACTOR = 1.3

  module_function

  def for(conversations:, sales:, cost_per_sale:, average_cost_per_sale:)
    return 'early' if conversations < MIN_CONVERSATIONS
    return 'review' if sales.zero?
    return 'signal' if sales < MIN_SALES || average_cost_per_sale.nil?
    return 'up' if cost_per_sale <= average_cost_per_sale
    return 'review' if cost_per_sale >= average_cost_per_sale * REVIEW_FACTOR

    'keep'
  end
end
