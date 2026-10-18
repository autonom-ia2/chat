require 'rails_helper'

# #1794: as listas dos Anúncios que levam a uma conversa mostram só as que a pessoa já veria.
RSpec.describe Crm::MetaAds::VisibleConversations do
  let(:account) { create(:account) }
  let(:dela) { create(:inbox, account: account) }
  let(:alheia) { create(:inbox, account: account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:da_caixa) { create(:conversation, account: account, inbox: dela) }
  let(:de_fora) { create(:conversation, account: account, inbox: alheia) }

  before { dela.add_members([agente.id]) }

  def filtro(user)
    described_class.new(account: account, account_user: user && AccountUser.find_by(account: account, user: user))
  end

  def advice
    { run_id: 1, actions: [
      { kind: 'stalled_quotes', cards: [{ id: 1, conversation_id: da_caixa.id }, { id: 2, conversation_id: de_fora.id }] },
      { kind: 'slow_response', cards: [] }
    ] }
  end

  it 'deixa nas propostas paradas só os cards de conversa visível' do
    filtrado = filtro(agente).advice(advice)

    expect(filtrado[:actions].first[:cards].pluck(:id)).to eq([1])
    expect(filtrado[:actions].second[:cards]).to eq([])
    expect(filtrado[:run_id]).to eq(1)
  end

  it 'mantém tudo para o administrador' do
    expect(filtro(admin).advice(advice)[:actions].first[:cards].pluck(:id)).to eq([1, 2])
  end

  it 'sem pessoa, nenhuma conversa' do
    expect(filtro(nil).ids([da_caixa.id])).to be_empty
  end

  it 'devolve o Advice sem ação como veio' do
    expect(filtro(agente).advice(nil)).to be_nil
  end
end
