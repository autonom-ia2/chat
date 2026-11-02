require 'rails_helper'

RSpec.describe Autonomia::Automacao::LimparRegistrosJob do
  it 'apaga os registros com mais de 30 dias e mantém os mais novos (F2.4)' do
    velho = travel_to(31.days.ago) { create(:autonomia_automacao_registro) }
    novo = travel_to(29.days.ago) { create(:autonomia_automacao_registro, execucao: velho.execucao) }

    described_class.perform_now

    expect(Autonomia::Automacao::Registro.where(id: [velho.id, novo.id])).to contain_exactly(novo)
  end

  it 'está agendado uma vez por dia' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(agenda['autonomia_automacao_limpar_registros_job']).to include('class' => described_class.name, 'cron' => '45 4 * * *')
  end
end
