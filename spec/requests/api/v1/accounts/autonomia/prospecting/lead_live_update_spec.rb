require 'rails_helper'

# Atualização ao vivo (#678, frente C): o evento prospecting.lead.updated leva o mesmo lead que a API devolve, para
# quem pode ver a Prospecção na conta. E a busca dispara, no servidor, o trabalho de cada lead.
RSpec.describe 'Autonomia prospecting lead live update', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/vivo', name: 'Clinica Ao Vivo', phone: '(41) 99999-0000',
      rating: 4.6, reviews_count: 12, enrichment_status: 'completed', enrichment_summary: 'Atende eventos',
      metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5541999990000' } }
    )
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  it 'emite prospecting.lead.updated com o payload do leads_controller, só para quem vê a Prospecção' do
    get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}", headers: auth_headers(admin)
    api_lead = response.parsed_body['payload']

    Autonomia::Prospecting::LeadBroadcaster.updated(lead)

    job = enqueued_jobs.find { |item| item['job_class'] == 'ActionCableBroadcastJob' }
    tokens, event, data = ActiveJob::Arguments.deserialize(job['arguments'])
    expect(event).to eq('prospecting.lead.updated')
    expect(tokens).to eq([admin.pubsub_token])
    expect(tokens).not_to include(agent.pubsub_token)
    expect(data['account_id']).to eq(account.id)
    expect(JSON.parse(data['lead'].to_json)).to eq(api_lead)
  end

  it 'a busca criada dispara no servidor o trabalho dos leads que voltaram' do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
    allow(Autonomia::Prospecting::LeadWorkQueue).to receive(:after_search)

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches",
         params: { search: { query: 'clinica', location: 'Curitiba, PR', requested_limit: 2,
                             metadata: { location_place_id: 'places/curitiba', location_latitude: -25.4, location_longitude: -49.2 } } },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    expect(Autonomia::Prospecting::LeadWorkQueue).to have_received(:after_search) do |account:, leads:|
      expect(account.id).to eq(lead.account_id)
      expect(leads.map(&:id)).to eq(response.parsed_body.dig('payload', 'leads').pluck('id'))
    end
  end
end
