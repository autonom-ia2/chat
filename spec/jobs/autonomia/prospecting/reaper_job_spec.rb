require 'rails_helper'

# O worker que morre no meio (deploy, OOM) deixa o lead "em andamento" para sempre: ninguém mais o
# marca como falho, e a tela recusa um novo pedido. O varredor devolve esses leads a um estado retomável.
RSpec.describe Autonomia::Prospecting::ReaperJob do
  let(:account) { create(:account) }

  def create_lead(name, **attributes)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{name}", name: name, **attributes)
  end

  before { allow(Autonomia::Prospecting::LeadBroadcaster).to receive(:updated) }

  it 'está agendado no config/schedule.yml' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    entry = schedule.values.find { |item| item['class'] == described_class.name }

    expect(entry).to include('queue' => 'scheduled_jobs')
    expect(entry['cron']).to be_present
  end

  it 'marca como falha retomável o enriquecimento preso em andamento há mais de 15 minutos' do
    running = create_lead('rodando', enrichment_status: 'running', enrichment_requested_at: 16.minutes.ago)
    queued = create_lead('na-fila', enrichment_status: 'queued', enrichment_requested_at: 40.minutes.ago)

    described_class.perform_now

    [running, queued].each do |lead|
      lead.reload
      expect(lead).to be_enrichment_failed
      expect(lead.enrichment_error).to eq('prospecting.enrichment.interrupted')
      expect(lead.enrichment_completed_at).to be_present
      expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: lead.id))
    end
  end

  it 'não mexe no que ainda está dentro do prazo nem no que já terminou' do
    recent = create_lead('recente', enrichment_status: 'running', enrichment_requested_at: 5.minutes.ago)
    done = create_lead('feito', enrichment_status: 'completed', enrichment_requested_at: 2.hours.ago)

    described_class.perform_now

    expect(recent.reload).to be_enrichment_running
    expect(done.reload).to be_enrichment_completed
    expect(Autonomia::Prospecting::LeadBroadcaster).not_to have_received(:updated)
  end

  it 'solta a verificação de WhatsApp presa na fila, para ser pedida de novo' do
    stuck = create_lead(
      'zap-preso', phone: '+5541999990000',
                   metadata: { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => 20.minutes.ago.iso8601 }, 'outro' => 'fica' }
    )
    recent = create_lead(
      'zap-recente', phone: '+5541999990001',
                     metadata: { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => 2.minutes.ago.iso8601 } }
    )

    described_class.perform_now

    expect(stuck.reload.metadata).to eq('outro' => 'fica')
    expect(recent.reload.metadata.dig('whatsapp_verification', 'status')).to eq('queued')
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: stuck.id))
  end
end
