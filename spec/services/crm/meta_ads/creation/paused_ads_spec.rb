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
                                      ad_id: ad_id, budget: budget, created_at: at)
  end

  def stub_ad(ad_id, effective, http: 200)
    body = http == 200 ? { id: ad_id, account_id: connection.ad_account_id, status: effective, effective_status: effective } : meta_graph_error(1)
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
    expect(list.first).to include(name: 'Anúncio 3', budget: budget.merge('active_ads_count' => 0))
    expect(a_request(:get, meta_graph_url('4')).with(query: hash_including({}))).not_to have_been_made
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
