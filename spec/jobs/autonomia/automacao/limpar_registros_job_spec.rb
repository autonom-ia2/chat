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

  # B3 do lote 3 (G55): a linha da campanha da vez é a trava contra mandar a mesma vez de novo. Só sai a vez fechada há
  # mais de CampanhaDaVez::RETENCAO e sem execução da vez ainda aberta; a aberta nunca sai.
  describe 'a campanha da vez' do
    let(:execucao) { create(:autonomia_automacao_execucao, estado: 'concluida', finalizada_em: 100.days.ago) }
    let(:marca) { 'recorrente:2026-01-01T12:00:00Z:card.recorrente' }

    def vez(ocorrencia, **atributos)
      Autonomia::Automacao::CampanhaDaVez.create!(account: execucao.account, automacao: execucao.automacao, ocorrencia: ocorrencia,
                                                  passo: 'c1', **atributos)
    end

    def da_vez(ocorrencia, estado:, finalizada_em: nil)
      create(:autonomia_automacao_execucao, versao: execucao.versao, estado: estado, finalizada_em: finalizada_em,
                                            chave_gatilho: 'card.recorrente', evento: "#{ocorrencia}:#{SecureRandom.random_number(10**6)}")
    end

    it 'apaga só a vez fechada há mais do prazo dela, sem execução aberta', :aggregate_failures do
      velha = travel_to(200.days.ago) { vez(marca, fechada_em: Time.current) }
      da_vez(marca, estado: 'concluida', finalizada_em: 199.days.ago)
      recente = vez("#{marca}x", fechada_em: 89.days.ago)
      aberta = travel_to(200.days.ago) { vez("#{marca}y") }
      com_espera = travel_to(200.days.ago) { vez("#{marca}z", fechada_em: Time.current) }
      da_vez("#{marca}z", estado: 'esperando')

      described_class.perform_now

      expect(Autonomia::Automacao::CampanhaDaVez.where(id: [velha, recente, aberta, com_espera].map(&:id)))
        .to contain_exactly(recente, aberta, com_espera)
    end

    it 'não depende do prazo do registro: a vez fechada há 31 dias fica' do
      fechada = travel_to(31.days.ago) { vez(marca, fechada_em: Time.current) }

      described_class.perform_now

      expect(Autonomia::Automacao::CampanhaDaVez.where(id: fechada.id)).to exist
    end
  end

  it 'está agendado uma vez por dia' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(agenda['autonomia_automacao_limpar_registros_job']).to include('class' => described_class.name, 'cron' => '45 4 * * *')
  end
end
