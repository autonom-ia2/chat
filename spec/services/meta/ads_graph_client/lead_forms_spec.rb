require 'rails_helper'

# Leitura dos leads de um formulário (#2195): página a página até o fim; no teto de segurança com mais páginas na Meta,
# devolve truncated, para quem chama avisar que cortou.
RSpec.describe Meta::AdsGraphClient::LeadForms do
  let(:client) { Meta::AdsGraphClient.new(access_token: 'page-token-de-teste') }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_leads(next_page:)
    paging = { cursors: { after: 'X' } }
    paging[:next] = 'https://graph.facebook.com/next' if next_page
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: 200, headers: json,
                                                               body: { data: [{ id: 'L1' }], paging: paging }.to_json)
  end

  it 'no teto com mais páginas na Meta: devolve o que leu e truncated' do
    stub_const('Meta::AdsGraphClient::LeadForms::LEADS_MAX_PAGES', 1)
    stub_leads(next_page: true)
    rows = []

    result, truncated = client.each_form_lead('9001', since: 90.days.ago) { |batch| rows.concat(batch) }

    expect(result.ok).to be(true)
    expect(truncated).to be(true)
    expect(rows.pluck('id')).to eq(['L1'])
  end

  it 'leu até o fim antes do teto: truncated falso' do
    stub_const('Meta::AdsGraphClient::LeadForms::LEADS_MAX_PAGES', 1)
    stub_leads(next_page: false)

    _result, truncated = client.each_form_lead('9001', since: 90.days.ago) { |_batch| nil }

    expect(truncated).to be(false)
  end
end
