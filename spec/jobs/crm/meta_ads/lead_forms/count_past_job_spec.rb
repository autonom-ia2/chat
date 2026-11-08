require 'rails_helper'

# Contagem de quem preencheu nos últimos 90 dias (#2195): guarda o número (e se cortou no teto) para a tela e solta a
# trava no fim, dê certo ou não, para a próxima abertura poder pedir de novo.
RSpec.describe Crm::MetaAds::LeadForms::CountPastJob do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:lock) { Crm::MetaAds::LeadForms::PastLeads.counting_key(account.id, '9001') }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 200, headers: json, body: { access_token: 'page-token' }.to_json)
    cache.write(lock, true)
  end

  def stub_leads(status: 200)
    body = status == 200 ? { data: [{ id: 'L1' }, { id: 'L2' }] } : meta_graph_error(100)
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: status, headers: json, body: body.to_json)
  end

  it 'guarda quantos preencheram e se cortou, e solta a trava' do
    stub_leads

    described_class.perform_now(account.id, '104882', '9001')

    expect(Crm::MetaAds::LeadForms::PastLeads.cached_count(account: account, page_id: '104882', form_id: '9001'))
      .to eq(count: 2, truncated: false)
    expect(cache.exist?(lock)).to be(false)
  end

  it 'a Meta recusa: não guarda número e solta a trava' do
    stub_leads(status: 400)

    described_class.perform_now(account.id, '104882', '9001')

    expect(cache.exist?(Crm::MetaAds::LeadForms::PastLeads.cache_key(account.id, '9001'))).to be(false)
    expect(cache.exist?(lock)).to be(false)
  end

  it 'sem a flag: não chama a Meta e solta a trava' do
    account.disable_features!('meta_ads_formularios')

    described_class.perform_now(account.id, '104882', '9001')

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(cache.exist?(lock)).to be(false)
  end
end
