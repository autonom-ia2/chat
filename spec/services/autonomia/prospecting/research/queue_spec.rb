require 'rails_helper'

# Fila da pesquisa de empresa e decisor (#679, frente C). Porta o contrato "all-N" da fila do Orth
# (lib/services/research/research-queue.test.ts): todo lead que a busca devolveu entra, uma vez só.
RSpec.describe Autonomia::Prospecting::Research::Queue do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:job) { Autonomia::Prospecting::Research::ResearchJob }

  def create_leads(count)
    Array.new(count) do |index|
      Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{index}", name: "Lead #{index}")
    end
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
  end

  describe '.after_search' do
    [1, 10, 11, 20, 25, 34, 60].each do |count|
      it "enfileira exatamente #{count} pesquisas para #{count} leads devolvidos" do
        leads = create_leads(count)

        described_class.after_search(account: account, leads: leads)

        expect(enqueued_jobs.count { |item| item['job_class'] == job.name }).to eq(count)
        expect(leads.map { |lead| lead.reload.company_research_status }.uniq).to eq(['queued'])
        expect(leads.map(&:decision_research_status).uniq).to eq(['queued'])
      end
    end

    it 'busca de 20 leads enfileira 20 pesquisas e repetir o disparo não duplica' do
      leads = create_leads(20)

      described_class.after_search(account: account, leads: leads)
      described_class.after_search(account: account, leads: leads)

      expect(enqueued_jobs.count { |item| item['job_class'] == job.name }).to eq(20)
      leads.each { |lead| expect(job).to have_been_enqueued.with(lead.id, false).exactly(:once) }
    end

    it 'o mesmo lead repetido na lista vira uma pesquisa só' do
      lead = create_leads(1).first

      described_class.after_search(account: account, leads: [lead, Autonomia::Prospecting::Lead.find(lead.id)])

      expect(job).to have_been_enqueued.exactly(:once)
    end

    it 'com a pesquisa desligada não enfileira nada nem muda o estado' do
      Autonomia::Prospecting::Config.disable_research_for!(account)
      leads = create_leads(3)

      described_class.after_search(account: account, leads: leads)

      expect(job).not_to have_been_enqueued
      expect(leads.map { |lead| lead.reload.company_research_status }.uniq).to eq(['not_researched'])
    end

    it 'o disparo automático só pesquisa quem nunca foi pesquisado' do
      fresh, done, failed = create_leads(3)
      done.update!(company_research_status: 'confirmed', decision_research_status: 'confirmed')
      failed.update!(company_research_status: 'failed', decision_research_status: 'failed')

      described_class.after_search(account: account, leads: [fresh, done, failed])

      expect(job).to have_been_enqueued.with(fresh.id, false).exactly(:once)
      expect(job).to have_been_enqueued.exactly(:once)
    end
  end

  describe '.enqueue' do
    let(:lead) { create_leads(1).first }

    it 'recusa um segundo pedido enquanto o lead está na fila, em pesquisa ou esperando a vez' do
      expect(described_class.enqueue(lead)).to be(true)
      expect(described_class.enqueue(lead)).to be(false)

      %w[researching waiting_capacity].each do |status|
        lead.update!(company_research_status: status, research_started_at: Time.current, research_requested_at: Time.current)
        expect(described_class.enqueue(lead)).to be(false)
      end
      expect(job).to have_been_enqueued.exactly(:once)
    end

    it 'aceita de novo um lead terminado e passa o force para o job' do
      lead.update!(company_research_status: 'confirmed', decision_research_status: 'confirmed', research_error: 'antigo')

      expect(described_class.enqueue(lead, force: true)).to be(true)

      expect(job).to have_been_enqueued.with(lead.id, true)
      expect(lead.reload).to have_attributes(company_research_status: 'queued', research_error: nil)
      expect(lead.research_requested_at).to be_within(5.seconds).of(Time.current)
    end

    it 'aceita um pedido preso há mais tempo que a espera máxima' do
      lead.update!(company_research_status: 'researching', research_started_at: 16.minutes.ago)

      expect(described_class.enqueue(lead)).to be(true)
    end
  end

  describe '.progress' do
    it 'conta total, concluídos, em pesquisa, na fila e falhas' do
      statuses = %w[not_researched queued waiting_capacity researching confirmed no_result ambiguous failed blocked]
      leads = create_leads(statuses.size).each_with_index.map do |lead, index|
        lead.tap { |item| item.update!(company_research_status: statuses[index]) }
      end

      expect(described_class.progress(leads)).to eq(total: 9, done: 5, running: 1, queued: 2, failed: 1)
    end
  end
end
