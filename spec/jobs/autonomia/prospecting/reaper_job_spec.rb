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

  it 'marca como falha retomável o enriquecimento rodando há mais de 15 minutos (worker que morreu)' do
    running = create_lead('rodando', enrichment_status: 'running', enrichment_requested_at: 16.minutes.ago)

    described_class.perform_now

    running.reload
    expect(running).to be_enrichment_failed
    expect(running.enrichment_error).to eq('prospecting.enrichment.interrupted')
    expect(running.enrichment_completed_at).to be_present
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: running.id))
  end

  # "queued" é o job esperando a vez na fila, não um worker morto. Antes o varredor o dava como falho aos 15 minutos
  # e, quando o job enfim rodava, achava failed e não fazia nada: a tela mostrava "falhou" em lead nunca tentado.
  it 'deixa na fila o enriquecimento que só está esperando a vez, e o job ainda enriquece depois' do
    queued = create_lead('na-fila', enrichment_status: 'queued', enrichment_requested_at: 40.minutes.ago)
    enricher = instance_double(Autonomia::Prospecting::LeadEnricher, perform: nil)
    allow(Autonomia::Prospecting::LeadEnricher).to receive(:new).and_return(enricher)

    described_class.perform_now
    expect(queued.reload).to be_enrichment_queued

    Autonomia::Prospecting::EnrichLeadJob.perform_now(queued.id)
    expect(enricher).to have_received(:perform)
  end

  it 'dá como falho o enriquecimento na fila há mais tempo do que qualquer espera normal' do
    lost = create_lead('perdido', enrichment_status: 'queued',
                                  enrichment_requested_at: Autonomia::Prospecting::LeadWorkQueue::QUEUED_STALE_AFTER.ago - 1.minute)

    described_class.perform_now

    expect(lost.reload).to be_enrichment_failed
    expect(lost.enrichment_error).to eq('prospecting.enrichment.interrupted')
  end

  it 'não mexe no que ainda está dentro do prazo nem no que já terminou' do
    recent = create_lead('recente', enrichment_status: 'running', enrichment_requested_at: 5.minutes.ago)
    done = create_lead('feito', enrichment_status: 'completed', enrichment_requested_at: 2.hours.ago)

    described_class.perform_now

    expect(recent.reload).to be_enrichment_running
    expect(done.reload).to be_enrichment_completed
    expect(Autonomia::Prospecting::LeadBroadcaster).not_to have_received(:updated)
  end

  # O VerifyWhatsappJob espera a trava da conta por até 20 minutos: soltar a marca aos 15 fazia a aba verificar de novo
  # o mesmo número que o job ainda ia verificar.
  it 'solta a verificação de WhatsApp presa na fila só depois da espera máxima da fila' do
    queued_at = (Autonomia::Prospecting::LeadWorkQueue::QUEUED_STALE_AFTER + 1.minute).ago.iso8601
    stuck = create_lead(
      'zap-preso', phone: '+5541999990000',
                   metadata: { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => queued_at }, 'outro' => 'fica' }
    )
    recent = create_lead(
      'zap-recente', phone: '+5541999990001',
                     metadata: { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => 25.minutes.ago.iso8601 } }
    )

    described_class.perform_now

    expect(stuck.reload.metadata).to eq('outro' => 'fica')
    expect(recent.reload.metadata.dig('whatsapp_verification', 'status')).to eq('queued')
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: stuck.id))
  end
end
