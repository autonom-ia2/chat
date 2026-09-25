require 'rails_helper'

# Enriquecimento em fila (#678, frente C): o pedido responde 202 na hora e o trabalho vai para o Sidekiq.
# Antes a requisição esperava site + IA (até 90 s) e devolvia o lead enriquecido.
RSpec.describe 'Autonomia prospecting lead enrichment queue', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/fila', name: 'Clinica Fila',
      website: 'https://clinicafila.example.com', phone: '+5541999990000'
    )
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/enrichment" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
    allow(Autonomia::Prospecting::LeadEnricher).to receive(:new)
  end

  it 'responde 202 em menos de 1 s, sem enriquecer na requisição, e enfileira o job' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    post path, headers: auth_headers(admin)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(response).to have_http_status(:accepted)
    expect(elapsed).to be < 1.0
    expect(Autonomia::Prospecting::LeadEnricher).not_to have_received(:new)
    expect(Autonomia::Prospecting::EnrichLeadJob).to have_been_enqueued.with(lead.id)
    expect(response.parsed_body.dig('payload', 'lead')).to include('id' => lead.id, 'enrichment_status' => 'queued')
    expect(lead.reload).to be_enrichment_queued
    expect(lead.enrichment_requested_at).to be_within(5.seconds).of(Time.current)
  end

  it 'recusa pedido duplicado enquanto o lead está na fila' do
    post path, headers: auth_headers(admin)
    clear_enqueued_jobs

    post path, headers: auth_headers(admin)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.errors.enrichment_in_progress'))
    expect(Autonomia::Prospecting::EnrichLeadJob).not_to have_been_enqueued
  end

  it 'recusa pedido duplicado enquanto o enriquecimento está rodando' do
    lead.update!(enrichment_status: 'running', enrichment_requested_at: 2.minutes.ago)

    post path, headers: auth_headers(admin)

    expect(response).to have_http_status(:conflict)
    expect(lead.reload).to be_enrichment_running
  end

  it 'aceita de novo um lead que falhou (falha é retomável)' do
    lead.update!(enrichment_status: 'failed', enrichment_error: 'prospecting.enrichment.interrupted')

    post path, headers: auth_headers(admin)

    expect(response).to have_http_status(:accepted)
    expect(lead.reload).to be_enrichment_queued
    expect(lead.enrichment_error).to be_nil
  end

  it 'aceita de novo um lead preso em andamento há mais de 15 minutos' do
    lead.update!(enrichment_status: 'running', enrichment_requested_at: 16.minutes.ago)

    post path, headers: auth_headers(admin)

    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Prospecting::EnrichLeadJob).to have_been_enqueued.with(lead.id)
  end

  it 'mantém a recusa da pesquisa desligada pelo superadmin, sem enfileirar' do
    Autonomia::Prospecting::Config.disable_research_for!(account)

    post path, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('prospecting.enrichment.disabled')
    expect(Autonomia::Prospecting::EnrichLeadJob).not_to have_been_enqueued
    expect(lead.reload).to be_enrichment_pending
  end
end
