require 'rails_helper'

# PastLeads lê desde `since:` (a reconciliação do #2285 passa o marco dela); sem ele, os últimos 90 dias, como no
# "trazer quem já preencheu".
RSpec.describe Crm::MetaAds::LeadForms::PastLeads do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:past) do
    described_class.new(account: account, page: { 'id' => '104882', 'access_token' => 'page-token' }, form: { 'id' => '9001', 'name' => 'Orçamento' },
                        **options)
  end

  before do
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: 200, headers: json, body: { data: [] }.to_json)
  end

  # Um segundo antes do marco: a Meta guarda o created_time em segundos (#2804).
  def filtering(since)
    [{ field: 'time_created', operator: 'GREATER_THAN', value: since.to_i - 1 }].to_json
  end

  context 'with since:' do
    let(:since) { 5.hours.ago.change(usec: 0) }
    let(:options) { { since: since } }

    it 'lê só desde o marco' do
      past.count!

      expect(a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering(since)))).to have_been_made.once
    end
  end

  context 'without since:' do
    let(:options) { {} }

    it 'lê os últimos 90 dias' do
      freeze_time do
        past.count!

        expect(a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering(90.days.ago))))
          .to have_been_made.once
      end
    end
  end
end
