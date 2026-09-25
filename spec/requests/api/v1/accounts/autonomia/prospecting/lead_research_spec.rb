require 'rails_helper'

# Pesquisa de empresa e decisor pela API (#679, frente C): o pedido responde 202 e roda no Sidekiq; o lead e o evento
# prospecting.lead.updated levam o bloco research, e a busca leva o progresso.
RSpec.describe 'Autonomia prospecting lead research', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:job) { Autonomia::Prospecting::Research::ResearchJob }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/pesquisa', name: 'Clinica Sorriso')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/research" }
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(
      cnpj: '12345678000190', legal_name: 'CLINICA SORRISO LTDA', trade_name: 'Clinica Sorriso', registration_status: 'ATIVA',
      registration_state: 'PR', legal_nature_code: '2062', legal_nature_text: 'Sociedade Empresária Limitada',
      verified_at: Time.zone.parse('2026-09-20 10:00'), owners: [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }]
    )
  end
  let(:researched_attributes) do
    {
      company_research_status: 'confirmed', decision_research_status: 'confirmed', company_profile: profile, research_reused: true,
      research_requested_at: Time.zone.parse('2026-09-25 09:00'), research_completed_at: Time.zone.parse('2026-09-25 09:01'),
      decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR', decision_confidence: 0.92,
      metadata: { 'research' => { 'owners' => [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }],
                                  'decision_source' => 'qsa', 'no_decision_reason' => nil } }
    }
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
  end

  describe 'POST leads/:id/research' do
    it 'responde 202, enfileira a pesquisa e devolve o lead na fila' do
      post path, headers: auth_headers(admin)

      expect(response).to have_http_status(:accepted)
      expect(job).to have_been_enqueued.with(lead.id, false)
      expect(response.parsed_body.dig('payload', 'lead', 'research')).to include('company_status' => 'queued', 'decision_status' => 'queued')
    end

    it 'verificar novamente com force ignora o reaproveitamento' do
      lead.update!(researched_attributes)

      post path, params: { force: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:accepted)
      expect(job).to have_been_enqueued.with(lead.id, true)
    end

    it 'pedido repetido com o lead na fila responde 202 sem enfileirar de novo' do
      post path, headers: auth_headers(admin)
      post path, headers: auth_headers(admin)

      expect(response).to have_http_status(:accepted)
      expect(job).to have_been_enqueued.exactly(:once)
    end

    it 'responde 422 com o código quando a pesquisa está desligada' do
      Autonomia::Prospecting::Config.disable_research_for!(account)

      post path, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'prospecting.research.disabled',
                                              'error' => I18n.t('autonomia.prospecting.errors.research_disabled'))
      expect(job).not_to have_been_enqueued
    end
  end

  describe 'bloco research' do
    it 'GET do lead leva empresa, sócios e decisor no formato do contrato' do
      lead.update!(researched_attributes)

      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}", headers: auth_headers(admin)

      expect(response.parsed_body.dig('payload', 'research')).to eq(
        'company_status' => 'confirmed', 'decision_status' => 'confirmed', 'reused' => true,
        'verified_at' => '2026-09-20T10:00:00Z', 'requested_at' => '2026-09-25T09:00:00Z', 'completed_at' => '2026-09-25T09:01:00Z',
        'error_code' => nil, 'no_decision_reason' => nil,
        'company' => { 'cnpj' => '12345678000190', 'legal_name' => 'CLINICA SORRISO LTDA', 'trade_name' => 'Clinica Sorriso',
                       'registration_status' => 'ATIVA', 'registration_state' => 'PR',
                       'legal_nature_text' => 'Sociedade Empresária Limitada' },
        'owners' => [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }],
        'decision' => { 'name' => 'ANA SOUZA', 'role' => 'SOCIO ADMINISTRADOR', 'confidence' => 0.92, 'source' => 'qsa',
                        'verified_at' => '2026-09-20T10:00:00Z' }
      )
    end

    it 'lead não pesquisado leva o bloco vazio, sem decisor mesmo com nome antigo da IA' do
      lead.update!(decision_name: 'Pessoa da IA', decision_confidence: 0.8)

      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}", headers: auth_headers(admin)

      expect(response.parsed_body.dig('payload', 'research')).to include(
        'company_status' => 'not_researched', 'decision_status' => 'not_researched', 'reused' => false, 'company' => nil,
        'owners' => [], 'decision' => nil, 'verified_at' => nil
      )
    end

    it 'o evento prospecting.lead.updated leva o mesmo bloco research' do
      lead.update!(researched_attributes)
      admin

      Autonomia::Prospecting::LeadBroadcaster.updated(lead)

      broadcast = enqueued_jobs.find { |item| item['job_class'] == 'ActionCableBroadcastJob' }
      _tokens, event, data = ActiveJob::Arguments.deserialize(broadcast['arguments'])
      expect(event).to eq('prospecting.lead.updated')
      expect(data.dig('lead', 'research')).to include('company_status' => 'confirmed', 'decision' => include('name' => 'ANA SOUZA'))
    end
  end

  describe 'research_progress da busca' do
    it 'conta os leads da busca por estado da pesquisa, e cada lead da busca leva o bloco research' do
      search = Autonomia::Prospecting::Search.create!(account: account, query: 'clinica', requested_limit: 4)
      statuses = %w[confirmed failed researching queued]
      leads = statuses.each_with_index.map do |status, index|
        Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/p#{index}", name: "Lead #{index}",
                                             search: search, company_research_status: status)
      end
      search.update!(metadata: { 'lead_ids' => leads.map(&:id) })

      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches/#{search.id}", headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(payload['research_progress']).to eq('total' => 4, 'done' => 1, 'running' => 1, 'queued' => 1, 'failed' => 1)
      expect(payload['leads'].map { |item| item.dig('research', 'company_status') }).to eq(statuses)
    end

    it 'a busca criada com a pesquisa ligada já volta com os leads na fila' do
      Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')

      post "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches",
           params: { search: { query: 'clinica', location: 'Curitiba, PR', requested_limit: 3,
                               metadata: { location_place_id: 'places/curitiba', location_latitude: -25.4, location_longitude: -49.2 } } },
           headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:created)
      expect(payload['leads'].map { |item| item.dig('research', 'company_status') }.uniq).to eq(['queued'])
      expect(payload.dig('search', 'research_progress')).to include('total' => payload['leads'].size, 'queued' => payload['leads'].size)
      payload['leads'].each { |item| expect(job).to have_been_enqueued.with(item['id'], false) }
    end
  end
end
