# Desfecho de um card conforme o funil (#1144). Quem fecha um card diz "deu certo" (won) ou "não deu" (lost); num funil
# que não conta como venda isso vira resolved/cancelled, para nunca entrar em venda, receita ou conversão de anúncio.
module Crm::Cards::Outcome
  SALE_STATUSES = %w[won lost].freeze
  NOT_SALE_STATUSES = %w[resolved cancelled].freeze
  CLOSED_STATUSES = (SALE_STATUSES + NOT_SALE_STATUSES).freeze
  NOT_SALE = { 'won' => 'resolved', 'lost' => 'cancelled' }.freeze
  SALE = NOT_SALE.invert.freeze

  def self.equivalent?(previous, current)
    NOT_SALE[previous] == current || SALE[previous] == current
  end

  def self.status_for(pipeline, status)
    status = status.to_s
    return status if pipeline.nil?

    pipeline.counts_as_sale? ? SALE.fetch(status, status) : NOT_SALE.fetch(status, status)
  end
end
