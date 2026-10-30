require 'rails_helper'

# "Pausados, esperando você ativar" (#2198, ponto 9): só os anúncios que a plataforma criou, lidos na Meta, e só os que
# continuam pausados. O orçamento vem do que foi gravado ao criar.
RSpec.describe Crm::MetaAds::Creation::PausedAds do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:budget) { { 'kind' => 'daily', 'amount' => 20.0, 'currency' => 'BRL', 'start_time' => '2026-10-27', 'end_time' => nil } }

  def created(ad_id, status: 'created', at: Time.current)
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: "k#{ad_id}", status: status, name: "Anúncio #{ad_id}",
                                      ad_id: ad_id, ad_account_id: connection.ad_account_id, budget: budget, created_at: at)
  end

  def stub_ad(ad_id, effective, http: 200, status: effective)
    body = http == 200 ? { id: ad_id, account_id: connection.ad_account_id, status: status, effective_status: effective } : meta_graph_error(1)
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(status: http, body: body.to_json, headers: json)
  end

  it 'lista só os criados aqui que seguem pausados, do mais novo para o mais velho' do
    created('1', at: 2.days.ago)
    created('2', at: 1.day.ago)
    created('3')
    created('4', status: 'rolled_back')
    stub_ad('1', 'PAUSED')
    stub_ad('2', 'ACTIVE')
    stub_ad('3', 'PAUSED')

    list = described_class.new(connection).list

    expect(list.pluck(:ad_id)).to eq(%w[3 1])
    expect(list.first).to include(name: 'Anúncio 3', budget: budget.merge('active_ads_count' => 0), in_review: false)
    expect(a_request(:get, meta_graph_url('4')).with(query: hash_including({}))).not_to have_been_made
  end

  # Por classe de effective_status (#2354, enum da doc do Ad): PAUSED, CAMPAIGN_PAUSED e ADSET_PAUSED prontos para
  # ativar; PENDING_REVIEW e IN_PROCESS em análise da Meta; o resto fica fora. Sempre com o próprio anúncio PAUSED.
  it 'anúncio pausado em análise da Meta entra na lista, marcado como em análise' do
    created('1', at: 2.days.ago)
    created('2', at: 1.day.ago)
    created('3')
    stub_ad('1', 'PENDING_REVIEW', status: 'PAUSED')
    stub_ad('2', 'IN_PROCESS', status: 'PAUSED')
    stub_ad('3', 'PAUSED')

    list = described_class.new(connection).list

    expect(list.map { |ad| ad.values_at(:ad_id, :in_review) }).to eq([['3', false], ['2', true], ['1', true]])
  end

  # Regra, não leitura real: em 29/10 o anúncio com os três níveis pausados veio PAUSED depois da análise. Se a Meta
  # devolver o nível de cima, o Ativar de um anúncio criado aqui liga os três, então ele também está pronto.
  it 'regra: anúncio pausado com a campanha ou o grupo pausados está pronto para ativar' do
    created('1', at: 1.day.ago)
    created('2')
    stub_ad('1', 'CAMPAIGN_PAUSED', status: 'PAUSED')
    stub_ad('2', 'ADSET_PAUSED', status: 'PAUSED')

    list = described_class.new(connection).list

    expect(list.map { |ad| ad.values_at(:ad_id, :in_review) }).to eq([['2', false], ['1', false]])
  end

  it 'fora da lista: anúncio ligado em análise e os outros estados de entrega' do
    others = %w[DISAPPROVED WITH_ISSUES PENDING_BILLING_INFO PREAPPROVED ARCHIVED DELETED ACTIVE]
    created('1')
    stub_ad('1', 'IN_PROCESS', status: 'ACTIVE')
    others.each_with_index do |effective, index|
      created((index + 2).to_s)
      stub_ad((index + 2).to_s, effective, status: 'PAUSED')
    end

    expect(described_class.new(connection).list).to eq([])
  end

  it 'anúncio que já foi ativado aqui não é lido de novo' do
    created('1').update!(activated_at: Time.current)

    expect(described_class.new(connection).list).to eq([])
    expect(a_request(:get, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'Meta fora do ar: erro, não lista vazia' do
    created('1')
    stub_ad('1', nil, http: 500)

    expect { described_class.new(connection).list }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
  end
end
