require 'rails_helper'

# #3101: o cron de madrugada roda o aprendizado do melhor horário.
RSpec.describe Autonomia::MelhorHorario::AprenderJob do
  it 'roda o aprendizado na fila das rotinas' do
    allow(Autonomia::MelhorHorario::Aprender).to receive(:rodar)

    described_class.perform_now

    expect(Autonomia::MelhorHorario::Aprender).to have_received(:rodar)
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end

  it 'está no config/schedule.yml' do
    entrada = YAML.load_file(Rails.root.join('config/schedule.yml'))['autonomia_melhor_horario_aprender_job']

    expect(entrada).to include('class' => described_class.name, 'queue' => 'scheduled_jobs')
  end
end
