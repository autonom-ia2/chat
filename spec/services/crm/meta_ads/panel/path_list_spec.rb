require 'rails_helper'

# O caminho do dinheiro clicável (#1110, F5): a lista de cada etapa sai da mesma coorte do painel, com o card e a
# conversa de cada linha, a proposta parada marcada e o tempo de resposta do mesmo período.
# Panel::ResponseTime é do construtor A e ainda pode não existir: aqui ele é stub pelo nome (verificado quando a
# classe existe; a integração roda sem stub).
# rubocop:disable RSpec/VerifiedDoubleReference
RSpec.describe Crm::MetaAds::Panel::PathList do
  let(:now) { Time.zone.parse('2026-10-07T15:00:00-03:00') }
  let(:response_time) { instance_double('Crm::MetaAds::Panel::ResponseTime', by_conversation: replies) }
  let(:replies) { {} }
  let!(:setup) { advisor_setup }
  let(:connection) { setup.last }
  # Uma conversa por dia, 04, 05 e 06/10 ao meio-dia: a primeira com proposta parada, a segunda com proposta
  # recente, a terceira com venda.
  let!(:chats) do
    advisor_insights(ad_id: 'A', adset_id: 'SA', from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 6), spend: 60, impressions: 6_000,
                     link_clicks: 60)
    advisor_conversations(ad_id: 'A', count: 3, from: Date.new(2026, 10, 4), to: Date.new(2026, 10, 6))
  end
  let!(:stalled) { advisor_stalled_quote(chats[0], waiting_days: 5) }
  let!(:fresh) { advisor_stalled_quote(chats[1], waiting_days: 0) }
  let!(:sale) { advisor_sale(chats[2]) }

  around { |example| travel_to(now) { example.run } }

  before do
    class_double('Crm::MetaAds::Panel::ResponseTime', new: response_time).as_stubbed_const
  end

  def list(step, days: 30)
    described_class.new(connection, step: step, days: days).payload
  end

  it 'conversas: a mais recente primeiro, com o card principal, o anúncio e o tempo de resposta' do
    lone = advisor_conversations(ad_id: nil, count: 1, from: Date.new(2026, 10, 7), to: Date.new(2026, 10, 7)).first
    replies.merge!(chats[2].id => { seconds: 120, answered: true }, lone.id => { seconds: nil, answered: false })

    payload = list('conversations')

    expect(payload).to include(step: 'conversations', days: 30, total: 4)
    expect(payload[:items].pluck(:conversation_id)).to eq([lone.id, chats[2].id, chats[1].id, chats[0].id])
    expect(payload[:items].first).to include(card_id: nil, title: lone.contact.name, ad_name: nil, stalled: false, answered: false)
    expect(payload[:items].second).to include(card_id: sale.id, title: 'Cotação', ad_name: 'Anúncio A', status: 'won', value: 1000.0,
                                              stage_name: 'Venda', response_seconds: 120, answered: true)
    expect(payload[:items].second[:touched_at]).to eq(Time.zone.parse('2026-10-06T12:00:00-03:00'))
    expect(Crm::MetaAds::Panel::ResponseTime).to have_received(:new).with(account_id: connection.account_id,
                                                                          range: Crm::MetaAds::Panel::Report.new(connection, days: 30).range)
  end

  it 'propostas: abertas pela espera mais antiga, depois as ganhas; a parada vem marcada' do
    items = list('quotes')[:items]

    expect(items.pluck(:card_id)).to eq([stalled.id, fresh.id, sale.id])
    expect(items.pluck(:stalled)).to eq([true, false, false])
    expect(items.first).to include(status: 'open', stage_name: 'Proposta', value: 1500.0, conversation_id: chats[0].id,
                                   response_seconds: nil, answered: nil)
    expect(items.first[:waiting_since]).to be_within(1.second).of(5.days.ago)
  end

  it 'vendas: do maior valor para o menor' do
    bigger = advisor_conversations(ad_id: 'A', count: 1, from: Date.new(2026, 10, 2), to: Date.new(2026, 10, 2)).first
    big_sale = advisor_sale(bigger)
    big_sale.update!(value_cents: 500_000)

    expect(list('sales')[:items].pluck(:card_id, :value)).to eq([[big_sale.id, 5000.0], [sale.id, 1000.0]])
  end

  it 'demoradas: sem resposta primeiro (a entrada mais antiga), depois a mais lenta; a rápida fica de fora' do
    replies.merge!(chats[0].id => { seconds: 60, answered: true }, chats[1].id => { seconds: 900, answered: true },
                   chats[2].id => { seconds: 301, answered: true })
    late = advisor_conversations(ad_id: 'A', count: 2, from: Date.new(2026, 10, 2), to: Date.new(2026, 10, 3), reply_after: nil)
    replies.merge!(late[1].id => { seconds: nil, answered: false }, late[0].id => { seconds: nil, answered: false })

    payload = list('slow_replies')

    expect(payload[:total]).to eq(4)
    expect(payload[:items].pluck(:conversation_id)).to eq([late[0].id, late[1].id, chats[1].id, chats[2].id])
    expect(payload[:items].third).to include(card_id: fresh.id, response_seconds: 900, answered: true)
  end

  it 'mostra no máximo LIST_LIMIT linhas, com o total da lista inteira' do
    stub_const("#{described_class}::LIST_LIMIT", 2)

    payload = list('quotes')

    expect(payload[:total]).to eq(3)
    expect(payload[:items].size).to eq(2)
  end

  it 'segue o período: em 7 dias, a conversa de 8 dias atrás sai' do
    old = advisor_conversations(ad_id: 'A', count: 1, from: Date.new(2026, 9, 29), to: Date.new(2026, 9, 29)).first

    expect(list('conversations', days: 30)[:items].pluck(:conversation_id)).to include(old.id)
    expect(list('conversations', days: 7)).to include(days: 7, total: 3)
  end

  it 'etapa fora da lista é erro de quem chama' do
    expect { list('spend') }.to raise_error(ArgumentError)
  end
end
# rubocop:enable RSpec/VerifiedDoubleReference
