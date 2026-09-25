require 'rails_helper'

RSpec.describe Autonomia::Prospecting::EnrichLeadJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/job', name: 'Clinica Job',
      website: 'https://clinicajob.example.com', enrichment_status: 'queued', enrichment_requested_at: Time.current
    )
  end
  let(:enricher) { instance_double(Autonomia::Prospecting::LeadEnricher) }

  before do
    allow(Autonomia::Prospecting::LeadEnricher).to receive(:new).with(lead: lead, user: nil).and_return(enricher)
    allow(Autonomia::Prospecting::LeadBroadcaster).to receive(:updated)
  end

  it 'enriquece pela assinatura do LeadEnricher e avisa a tela com o lead atualizado' do
    allow(enricher).to receive(:perform) { lead.update!(enrichment_status: 'completed') }

    described_class.perform_now(lead.id)

    expect(enricher).to have_received(:perform)
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: lead.id, enrichment_status: 'completed'))
  end

  it 'manda verificar o WhatsApp achado no site depois de enriquecer' do
    allow(enricher).to receive(:perform) { lead.update!(enrichment_status: 'completed', enriched_whatsapp: '+5541988887777') }

    described_class.perform_now(lead.id)

    expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [lead.id])
  end

  it 'não verifica WhatsApp quando o site não trouxe número' do
    allow(enricher).to receive(:perform) { lead.update!(enrichment_status: 'completed') }

    described_class.perform_now(lead.id)

    expect(Autonomia::Prospecting::VerifyWhatsappJob).not_to have_been_enqueued
  end

  it 'falha honesta do enriquecimento não relança (não há retry do Sidekiq) e avisa a tela' do
    allow(enricher).to receive(:perform) do
      lead.update!(enrichment_status: 'failed', enrichment_error: 'site fora')
      raise Autonomia::Prospecting::LeadEnricher::Error, 'site fora'
    end

    expect { described_class.perform_now(lead.id) }.not_to raise_error

    expect(lead.reload).to be_enrichment_failed
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated)
  end

  it 'trabalho que morre por erro inesperado vira falha retomável' do
    allow(enricher).to receive(:perform).and_raise(ActiveRecord::ConnectionTimeoutError, 'pool esgotado')

    expect { described_class.perform_now(lead.id) }.not_to raise_error

    lead.reload
    expect(lead).to be_enrichment_failed
    expect(lead.enrichment_error).to eq('prospecting.enrichment.interrupted')
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated)
    expect(Autonomia::Prospecting::LeadWorkQueue.enqueue_enrichment(lead)).to be(true)
  end

  it 'não roda de novo um lead que já saiu da fila (pedido antigo, varrido ou já feito)' do
    lead.update!(enrichment_status: 'completed')

    described_class.perform_now(lead.id)

    expect(Autonomia::Prospecting::LeadEnricher).not_to have_received(:new)
    expect(Autonomia::Prospecting::LeadBroadcaster).not_to have_received(:updated)
  end

  it 'ignora lead apagado' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
