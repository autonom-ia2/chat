require 'rails_helper'

# #2858 (F5): a rodada das bases. Passado o horário da stack, enfileira UMA base vencida por vez (a próxima entra quando
# a anterior termina), pula a que já tentou hoje, e nada sem conta com a flag das bases.
RSpec.describe Autonomia::FerramentasProntas::AtualizarBasesJob do
  include ActiveJob::TestHelper

  let(:estado) { Autonomia::FerramentasProntas::Bases::Estado }
  let(:fila) { Autonomia::FerramentasProntas::AtualizarBaseJob }
  let(:rodada) { Autonomia::FerramentasProntas::AtualizarBaseJob::RODADA }

  around do |example|
    travel_to(Time.zone.parse('2026-11-11 10:47 UTC')) do
      with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: '10:47') { example.run }
    end
  end

  def enfileiradas
    enqueued_jobs.select { |job| job['job_class'] == fila.name }.map { |job| job['arguments'].first }
  end

  def ligar
    create(:account).enable_features!(Autonomia::FerramentasProntas::Bases::FLAG)
  end

  it 'sem nenhuma conta com a flag das bases, não enfileira nada (nada é baixado)' do
    create(:account)

    expect { described_class.perform_now }.not_to have_enqueued_job(fila)
  end

  it 'uma base por vez: enfileira só a primeira vencida (a nunca baixada, a diária de ontem, a mensal do 28º dia)' do
    ligar
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 2.hours.ago)
    estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: 1.day.ago)
    estado.create!(base: 'geracao_solar', geracao_ativa: 1, atualizado_em: 27.days.ago)
    estado.create!(base: 'transportadoras', geracao_ativa: 1, atualizado_em: 28.days.ago)

    described_class.perform_now

    expect(enfileiradas).to eq(['aeronaves'])
  end

  it 'pula a base que já tentou hoje (falhou): ela tenta de novo amanhã, e a próxima vencida entra' do
    ligar
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.day.ago, tentado_em: 1.minute.ago, falhou_em: 1.minute.ago)
    estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: 1.day.ago)

    described_class.perform_now

    expect(enfileiradas).to eq(['aeronaves'])
  end

  it 'antes do horário da stack, nada; o horário vem do ENV, e sem ele cada stack tem o seu (pelo endereço)' do
    ligar
    with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: '11:30') { described_class.perform_now }
    expect(enfileiradas).to be_empty

    with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: nil, FRONTEND_URL: 'https://app.um.exemplo.test') do
      um = described_class.horario
      outro = with_modified_env(FRONTEND_URL: 'https://app.dois.exemplo.test') { described_class.horario }
      expect([um, outro]).to all(be_between('10:00', '11:55'))
      expect(um).not_to eq(outro)
    end
  end

  it 'T28: atualizou pelo job às 10:47:30; 28 dias depois, na rodada das 10:47:00, a mensal entra na fila' do
    ligar
    estado.create!(base: 'transportadoras', geracao_ativa: 1, atualizado_em: Time.zone.parse('2026-10-14 10:47:30 UTC'))
    %w[planos_de_saude aeronaves queimadas].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 1.hour.ago) }
    estado.create!(base: 'geracao_solar', geracao_ativa: 1, atualizado_em: 2.days.ago)

    described_class.perform_now

    expect(enfileiradas).to eq(['transportadoras'])
  end

  describe Autonomia::FerramentasProntas::AtualizarBaseJob do
    let(:importacao) { instance_double(Autonomia::FerramentasProntas::Bases::Importacao, call: :atualizada) }

    before do
      ligar
      allow(Autonomia::FerramentasProntas::Bases::Importacao).to receive(:new).and_return(importacao)
    end

    after { Redis::Alfred.delete(rodada) }

    it 'base que não existe não faz nada' do
      fila.perform_now('nao_existe')

      expect(Autonomia::FerramentasProntas::Bases::Importacao).not_to have_received(:new)
    end

    it 'importa a base e, ao terminar, chama a rodada de novo (a próxima base entra)' do
      expect { fila.perform_now('planos_de_saude') }.to have_enqueued_job(Autonomia::FerramentasProntas::AtualizarBasesJob)

      expect(importacao).to have_received(:call)
      expect(Redis::Alfred.get(rodada)).to be_nil
    end

    it 'outra base importando (trava da rodada): não importa agora; a rodada seguinte tenta' do
      Redis::Alfred.set(rodada, 'outra', nx: true, ex: 60)

      fila.perform_now('planos_de_saude')

      expect(Autonomia::FerramentasProntas::Bases::Importacao).not_to have_received(:new)
      expect(Redis::Alfred.get(rodada)).to eq('outra')
    end

    it 'confere de novo depois da trava: a base que outra rodada já atualizou não baixa outra vez' do
      estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.minute.ago)

      fila.perform_now('planos_de_saude')

      expect(Autonomia::FerramentasProntas::Bases::Importacao).not_to have_received(:new)
    end
  end
end
