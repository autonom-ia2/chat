require 'rails_helper'

# Disparo no servidor ao fim da busca (#678, frente C): enriquecer e verificar o WhatsApp não depende mais
# da aba aberta.
RSpec.describe Autonomia::Prospecting::LeadWorkQueue do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:waha_env) { { 'WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste' } }
  let(:leads) do
    Array.new(3) do |index|
      Autonomia::Prospecting::Lead.create!(
        account: account, provider: 'mock', provider_place_id: "places/#{index}", name: "Lead #{index}", phone: "(41) 99999-000#{index}"
      )
    end
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-prospeccao' })
  end

  def after_search(items = leads)
    with_modified_env(waha_env) { described_class.after_search(account: account, leads: items) }
  end

  describe '.after_search' do
    it 'com a pesquisa ligada, enfileira o enriquecimento de cada lead ainda não enriquecido' do
      Autonomia::Prospecting::Config.enable_research_for!(account)
      leads.last.update!(enrichment_status: 'completed')

      after_search

      leads.first(2).each do |lead|
        expect(Autonomia::Prospecting::EnrichLeadJob).to have_been_enqueued.with(lead.id)
        expect(lead.reload).to be_enrichment_queued
      end
      expect(Autonomia::Prospecting::EnrichLeadJob).not_to have_been_enqueued.with(leads.last.id)
    end

    it 'com a pesquisa desligada, não enriquece, mas verifica o WhatsApp' do
      after_search

      expect(Autonomia::Prospecting::EnrichLeadJob).not_to have_been_enqueued
      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, leads.map(&:id))
      leads.each { |lead| expect(lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('queued') }
    end

    it 'não reenfileira quem já tem verificação nem quem não tem telefone' do
      leads[0].update!(metadata: { 'whatsapp_verification' => { 'status' => 'not_whatsapp' } })
      leads[1].update!(phone: nil)

      after_search

      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [leads[2].id])
      expect(leads[0].reload.metadata.dig('whatsapp_verification', 'status')).to eq('not_whatsapp')
    end

    it 'inclui o lead que só tem o WhatsApp achado no site ainda não verificado' do
      leads.each { |lead| lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'verified' } }) }
      leads[1].update!(enriched_whatsapp: '(41) 98888-7777')

      after_search

      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [leads[1].id])
      expect(leads[1].reload.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
    end

    it 'divide a verificação em lotes' do
      stub_const("#{described_class}::WHATSAPP_BATCH_SIZE", 2)

      after_search

      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, leads.first(2).map(&:id))
      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [leads.last.id])
    end

    it 'sem WAHA configurado, não marca nem enfileira verificação' do
      described_class.after_search(account: account, leads: leads)

      expect(Autonomia::Prospecting::VerifyWhatsappJob).not_to have_been_enqueued
      expect(leads.first.reload.metadata).not_to have_key('whatsapp_verification')
    end

    it 'com o módulo desligado, não faz nada' do
      Autonomia::Prospecting::Config.enable_research_for!(account)
      Autonomia::Prospecting::Config.disable_for!(account)

      after_search

      expect(Autonomia::Prospecting::EnrichLeadJob).not_to have_been_enqueued
      expect(Autonomia::Prospecting::VerifyWhatsappJob).not_to have_been_enqueued
      expect(leads.first.reload).to be_enrichment_pending
    end
  end

  describe '.enqueue_enrichment' do
    let(:lead) { leads.first }

    it 'recusa o segundo pedido enquanto o primeiro está na fila' do
      expect(described_class.enqueue_enrichment(lead)).to be(true)
      expect(described_class.enqueue_enrichment(lead)).to be(false)
      expect(Autonomia::Prospecting::EnrichLeadJob).to have_been_enqueued.exactly(:once)
    end
  end
end
