require 'rails_helper'

# Veredito por anúncio (#1088, CA-3.2): poucos dados nunca viram aumentar ou pausar.
RSpec.describe Crm::MetaAds::Panel::Verdict do
  def verdict(conversations:, sales:, cost: nil, average: 100.0)
    described_class.for(conversations: conversations, sales: sales, cost_per_sale: cost, average_cost_per_sale: average)
  end

  it 'menos de 20 conversas é sempre "ainda é cedo", mesmo vendendo bem' do
    expect(verdict(conversations: 19, sales: 5, cost: 10.0)).to eq('early')
  end

  it 'com base de conversas e nenhuma venda pede revisar o anúncio' do
    expect(verdict(conversations: 20, sales: 0)).to eq('review')
  end

  it 'uma ou duas vendas são sinal inicial' do
    expect(verdict(conversations: 30, sales: 2, cost: 50.0)).to eq('signal')
  end

  it 'com base suficiente compara o custo por venda com a média da conta' do
    expect(verdict(conversations: 30, sales: 3, cost: 90.0)).to eq('up')
    expect(verdict(conversations: 30, sales: 3, cost: 110.0)).to eq('keep')
    expect(verdict(conversations: 30, sales: 3, cost: 130.0)).to eq('review')
  end
end
