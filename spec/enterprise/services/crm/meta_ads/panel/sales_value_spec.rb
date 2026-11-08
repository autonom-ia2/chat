require 'rails_helper'

# Valores de venda em R$ nos Anúncios (#2075, lote 13): o dinheiro que sai do valor dos cards segue o
# Crm::ValorDeVenda. Gasto, custo, veredito e contagens ficam com quem já vê o painel.
RSpec.describe Crm::MetaAds::Panel::SalesValue do
  let(:now) { Time.zone.parse('2026-10-07T15:00:00-03:00') }
  let!(:setup) { advisor_setup }
  let(:account) { setup.first }
  let(:connection) { setup.last }
  let(:inbox) { account.inboxes.sole }
  let(:admin) { AccountUser.find_by!(account: account, role: :administrator).user }
  let(:sem_chave) { pessoa_com(%w[meta_ads_view conversation_manage]) }
  let(:com_chave) { pessoa_com(%w[meta_ads_view conversation_manage sales_value_view]) }
  let(:chats) do
    advisor_insights(ad_id: 'A', adset_id: 'SA', from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 6), spend: 60, impressions: 6_000,
                     link_clicks: 60)
    advisor_conversations(ad_id: 'A', count: 3, from: Date.new(2026, 10, 4), to: Date.new(2026, 10, 6))
  end
  # A proposta parada é do administrador; a venda grande (R$ 5.000, fechada em 05/10) também; a pequena (R$ 1.000,
  # fechada em 06/10) é de quem não tem a chave.
  let!(:parada) { advisor_stalled_quote(chats[0], waiting_days: 5).tap { |card| card.update!(owner: admin) } }
  let!(:grande) { venda(chats[1], 500_000, Time.zone.parse('2026-10-05T10:00:00-03:00'), admin) }
  let!(:pequena) { venda(chats[2], 100_000, Time.zone.parse('2026-10-06T10:00:00-03:00'), sem_chave.user) }

  around { |example| travel_to(now) { example.run } }

  before { Redis::Alfred.delete(advisor_facts_key(connection, connection.ad_account_today)) }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    inbox.add_members([user.id])
    AccountUser.find_by(account: account, user: user).tap do |account_user|
      account_user.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    end
  end

  def venda(conversation, cents, closed_at, owner)
    advisor_sale(conversation).tap do |card|
      card.update!(value_cents: cents, owner: owner)
      card.update_columns(closed_at: closed_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def olhar(account_user)
    Crm::MetaAds::VisibleConversations.new(account: account, account_user: account_user)
  end

  def membro(user) = AccountUser.find_by(account: account, user: user)

  def painel(account_user)
    Crm::MetaAds::Panel::Report.new(connection, period: '30d', visible: olhar(account_user)).payload
  end

  def anuncio(account_user, ad_id = 'A')
    Crm::MetaAds::Panel::AdDetail.new(connection, ad_id: ad_id, period: '30d', visible: olhar(account_user)).payload
  end

  def vendas(account_user)
    Crm::MetaAds::Panel::PathList.new(connection, step: 'sales', period: '30d', visible: olhar(account_user)).payload[:items]
  end

  describe 'o painel' do
    it 'sem a chave: sem o dinheiro dos cards, com gasto, custo, veredito e contagens' do
      payload = painel(sem_chave)

      expect(payload[:totals]).to include(sales: 2, sales_value: nil, return_per_real: nil, open: 1, open_value: nil, value_hidden: true,
                                          spend: 60.0, cost_per_sale: 30.0, conversations: 3, quotes: 3)
      expect(payload[:ads].sole).to include(ad_id: 'A', sales: 2, sales_value: nil, open_value: nil, value_hidden: true, spend: 60.0,
                                            cost_per_sale: 30.0)
      expect(payload[:ads].sole[:verdict]).to be_present
    end

    it 'com a chave, o administrador e o agente sem função veem o valor' do
      agente = membro(create(:user, account: account, role: :agent))

      [com_chave, membro(admin), agente].each do |account_user|
        totals = painel(account_user)[:totals]

        expect(totals).to include(sales_value: 6000.0, return_per_real: 100.0, open_value: 1500.0)
        expect(totals).not_to have_key(:value_hidden)
      end
    end

    it 'sem pessoa (o consultor e o resumo, que trabalham pela conta) vê tudo' do
      expect(Crm::MetaAds::Panel::Report.new(connection, period: '30d').payload[:totals]).to include(sales_value: 6000.0)
    end

    it 'o anúncio que não traz conversa (só gasto, sem veredito) passa inteiro, e a tela dele não quebra' do
      advisor_insights(ad_id: 'B', adset_id: 'SB', from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 6), spend: 30, impressions: 3_000,
                       link_clicks: 30)
      Crm::MetaAdObject.create!(account: account, meta_object_id: 'SB', object_type: 'adset', destination_type: 'WEBSITE', fetched_at: now)

      payload = painel(sem_chave)

      expect(payload[:other_ads].sole).to include(ad_id: 'B', spend: 30.0)
      expect(payload[:other_ads].sole).not_to have_key(:value_hidden)
      expect(payload[:totals]).to include(other_spend: 30.0)
      expect(anuncio(sem_chave, 'B')).to include(ad_id: 'B', verdict: nil, sales_value: nil, value_hidden: true, spend: 30.0)
    end
  end

  describe 'o anúncio por dentro' do
    it 'sem a chave: o anúncio sem o dinheiro e cada proposta sem valor, menos a de que a pessoa é dona' do
      payload = anuncio(sem_chave)

      expect(payload).to include(sales_value: nil, value_hidden: true, spend: 60.0)
      expect(payload[:reason]).to be_present
      valores = payload[:quotes_list].to_h { |quote| [quote[:card_id], quote.slice(:value, :value_hidden)] }
      expect(valores).to eq(parada.id => { value: nil, value_hidden: true }, grande.id => { value: nil, value_hidden: true },
                            pequena.id => { value: 1000.0 })
    end

    it 'com a chave, tudo' do
      payload = anuncio(com_chave)

      expect(payload).to include(sales_value: 6000.0)
      expect(payload[:quotes_list].pluck(:value)).to contain_exactly(1500.0, 5000.0, 1000.0)
    end
  end

  describe 'a lista das vendas' do
    it 'sem a chave, da venda mais recente para a mais antiga, e só o valor do card dela' do
      expect(vendas(sem_chave).map { |item| [item[:card_id], item[:value]] }).to eq([[pequena.id, 1000.0], [grande.id, nil]])
      expect(vendas(sem_chave).second).to include(value_hidden: true)
    end

    it 'com a chave, do maior valor para o menor' do
      expect(vendas(com_chave).map { |item| [item[:card_id], item[:value]] }).to eq([[grande.id, 5000.0], [pequena.id, 1000.0]])
    end
  end

  describe 'o consultor' do
    def paradas(account_user)
      advice = Crm::MetaAds::Advisor::Analysis.current(connection, locale: 'pt_BR', shown: false, visible: olhar(account_user))
      advice[:actions].find { |action| action[:kind] == 'stalled_quotes' }
    end

    def texto_da_ia!
      paradas(com_chave)
      action = Crm::MetaAdvisorAction.find_by!(account_id: account.id, kind: 'stalled_quotes')
      texts = { 'headline' => 'São {{count}} propostas paradas', 'body' => 'Juntas, somam {{value}}.', 'why' => 'Há {{days}} dias sem conversa.' }
      Crm::MetaAdvisorRun.where(account_id: account.id).find_each do |run|
        run.update!(writer_status: 'written', texts: { "stalled_quotes|#{action.subject_key}" => texts })
      end
    end

    it 'sem a chave: a soma sai dos fatos e o card fica sem valor' do
      action = paradas(sem_chave)

      expect(action[:facts]).to include('count' => 1, 'days' => 3)
      expect(action[:facts]).not_to have_key('value')
      expect(action[:cards].sole).to include(id: parada.id, value: nil, value_hidden: true)
    end

    it 'com a chave, a soma e o valor do card' do
      action = paradas(com_chave)

      expect(action[:facts]).to include('value' => 1500.0)
      expect(action[:cards].sole).to include(id: parada.id, value: 1500.0)
    end

    it 'o texto da IA que usa a soma volta ao texto da regra para quem não tem a chave' do
      texto_da_ia!

      expect(paradas(com_chave)).to include(source: 'ai', body: 'Juntas, somam R$ 1.500.')
      expect(paradas(sem_chave)).to include(source: 'rule', headline: nil, body: nil, why: nil)
    end
  end

  it '.hide não quebra a linha que já vem sem valor' do
    expect(described_class.hide({ ad_id: 'B', spend: 30.0 })).to eq(ad_id: 'B', spend: 30.0, value_hidden: true)
    expect(described_class.hide({ sales_value: nil, sales: 0 })).to eq(sales_value: nil, sales: 0, value_hidden: true)
  end
end
