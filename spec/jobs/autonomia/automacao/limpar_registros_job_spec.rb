require 'rails_helper'

RSpec.describe Autonomia::Automacao::LimparRegistrosJob do
  it 'apaga os registros com mais de 30 dias e mantém os mais novos (F2.4)' do
    execucao = create(:autonomia_automacao_execucao, estado: 'concluida')
    velho = travel_to(31.days.ago) { create(:autonomia_automacao_registro, execucao: execucao) }
    novo = travel_to(29.days.ago) { create(:autonomia_automacao_registro, execucao: execucao) }

    described_class.perform_now

    expect(Autonomia::Automacao::Registro.where(id: [velho.id, novo.id])).to contain_exactly(novo)
  end

  it 'mantém o registro velho da execução ainda aberta: a espera longa guarda nele o começo (#2750)' do
    aberta = create(:autonomia_automacao_execucao, estado: 'esperando')
    velho = travel_to(31.days.ago) { create(:autonomia_automacao_registro, execucao: aberta) }

    described_class.perform_now

    expect(Autonomia::Automacao::Registro.where(id: velho.id)).to exist
  end

  it 'apaga as execuções finalizadas há mais de 90 dias que já não têm registro (#2459)', :aggregate_failures do
    velha = travel_to(91.days.ago) { create(:autonomia_automacao_execucao, estado: 'concluida') }
    com_registro = travel_to(91.days.ago) { create(:autonomia_automacao_execucao, estado: 'falhou', chave_gatilho: 'b') }
    create(:autonomia_automacao_registro, execucao: com_registro)
    recente = travel_to(89.days.ago) { create(:autonomia_automacao_execucao, estado: 'concluida', chave_gatilho: 'c') }
    aberta = travel_to(91.days.ago) { create(:autonomia_automacao_execucao, estado: 'esperando', chave_gatilho: 'd') }

    described_class.perform_now

    expect(Autonomia::Automacao::Execucao.where(id: [velha, com_registro, recente, aberta].map(&:id)))
      .to contain_exactly(com_registro, recente, aberta)
  end

  it 'está agendado uma vez por dia' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(agenda['autonomia_automacao_limpar_registros_job']).to include('class' => described_class.name, 'cron' => '45 4 * * *')
  end
end
