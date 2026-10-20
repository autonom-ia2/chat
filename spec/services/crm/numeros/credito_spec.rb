require 'rails_helper'

RSpec.describe Crm::Numeros::Credito do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:sale) { create_crm_pipeline(account: account, user: ana) }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Suporte', created_by: ana, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end
  let(:month) { Crm::Numeros::Mes.new(account: account) }

  around { |example| travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run } }

  def card(pipeline_and_stage, owner:, value_cents: 0, currency: 'BRL')
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, title: "Card #{SecureRandom.hex(3)}",
                              value_cents: value_cents, currency: currency)
  end

  def close(card, result, actor: nil)
    Crm::Cards::Closer.new(card: card, actor: actor, result: result).perform
  end

  def credito_de(user)
    described_class.new(account: account, user: user, range: month.range).perform
  end

  it 'credita 100% a quem era o responsável no fechamento, não a quem é o dono depois nem a quem clicou' do
    venda = card(sale, owner: ana, value_cents: 300_000)
    close(venda, 'won', actor: bruno)
    venda.update!(owner: bruno)

    expect(credito_de(ana)).to include(vendas: 1, valores: { 'BRL' => 300_000 }, resolvidos: 0, estimado: false)
    expect(credito_de(bruno)).to include(vendas: 0, valores: {}, estimado: false)
  end

  it 'venda antiga sem o registro do fechamento conta pelo responsável atual e marca a estimativa' do
    antiga = card(sale, owner: bruno, value_cents: 50_000)
    antiga.update!(status: :won)

    expect(credito_de(bruno)).to include(vendas: 1, valores: { 'BRL' => 50_000 }, estimado: true)
    expect(credito_de(ana)).to include(vendas: 0, estimado: false)
  end

  it 'vale o último fechamento: reaberta e ganha de novo por outra pessoa' do
    venda = card(sale, owner: ana, value_cents: 10_000)
    close(venda, 'won')
    close(venda, 'reopen')
    venda.update!(owner: bruno)
    close(venda, 'won')

    expect(credito_de(bruno)[:vendas]).to eq(1)
    expect(credito_de(ana)[:vendas]).to eq(0)
  end

  it 'conta resolvido no funil de Atender e deixa de fora o fechado fora do mês e o sem responsável' do
    close(card(service, owner: ana), 'won')
    fora = card(sale, owner: ana, value_cents: 9_000)
    close(fora, 'won')
    fora.update!(closed_at: Time.utc(2026, 9, 30, 12, 0))
    close(card(sale, owner: nil, value_cents: 7_000), 'won')

    expect(credito_de(ana)).to include(vendas: 0, resolvidos: 1, valores: {})
  end

  it 'separa as moedas e devolve os cards ganhos da pessoa' do
    brl = card(sale, owner: ana, value_cents: 1_000)
    usd = card(sale, owner: ana, value_cents: 2_000, currency: 'USD')
    [brl, usd].each { |venda| close(venda, 'won') }

    result = credito_de(ana)

    expect(result[:valores]).to eq('BRL' => 1_000, 'USD' => 2_000)
    expect(result[:ganhos]).to contain_exactly(brl.id, usd.id)
  end
end
