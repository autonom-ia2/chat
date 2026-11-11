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

  it 'as diárias pequenas vêm primeiro: queimadas, planos de saúde, aeronaves; depois as mensais' do
    expect(Autonomia::FerramentasProntas::Bases.importadores.map(&:chave))
      .to eq(%w[queimadas planos_de_saude aeronaves geracao_solar transportadoras])
  end

  it 'uma base por vez: enfileira só a primeira vencida (a nunca baixada, a diária de ontem, a mensal do 28º dia)' do
    ligar
    estado.create!(base: 'queimadas', geracao_ativa: 1, atualizado_em: 2.hours.ago)
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 2.hours.ago)
    estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: 1.day.ago)
    estado.create!(base: 'geracao_solar', geracao_ativa: 1, atualizado_em: 27.days.ago)
    estado.create!(base: 'transportadoras', geracao_ativa: 1, atualizado_em: 28.days.ago)

    described_class.perform_now

    expect(enfileiradas).to eq(['aeronaves'])
  end

  it 'pula a base que já tentou hoje (falhou): ela tenta de novo amanhã, e a próxima vencida entra' do
    ligar
    estado.create!(base: 'queimadas', geracao_ativa: 1, atualizado_em: 2.hours.ago)
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.day.ago, tentado_em: 1.minute.ago, falhou_em: 1.minute.ago)
    estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: 1.day.ago)

    described_class.perform_now

    expect(enfileiradas).to eq(['aeronaves'])
  end

  it 'queimadas que falhou tenta de novo no mesmo dia, 3 horas depois da última; as outras só amanhã' do
    ligar
    estado.create!(base: 'queimadas', geracao_ativa: 1, atualizado_em: 1.day.ago, tentado_em: 2.hours.ago, falhou_em: 2.hours.ago)
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.day.ago, tentado_em: 4.hours.ago, falhou_em: 4.hours.ago)
    %w[aeronaves].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 1.hour.ago) }
    %w[geracao_solar transportadoras].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 2.days.ago) }

    described_class.perform_now
    expect(enfileiradas).to be_empty

    travel 1.hour + 1.minute
    described_class.perform_now
    expect(enfileiradas).to eq(['queimadas'])
  end

  it 'a rodada que morreu no meio (trava da RODADA presa) tenta de novo 3 horas depois, já com as travas vencidas' do
    ligar
    %w[queimadas aeronaves].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 1.hour.ago) }
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.day.ago, tentado_em: 2.hours.ago)
    %w[geracao_solar transportadoras].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 2.days.ago) }

    described_class.perform_now
    expect(enfileiradas).to be_empty

    travel 1.hour + 1.minute
    described_class.perform_now
    expect(enfileiradas).to eq(['planos_de_saude'])
    expect(Autonomia::FerramentasProntas::AtualizarBaseJob::VALIDADE_DA_RODADA).to be < 3.hours
    expect(Autonomia::FerramentasProntas::Bases::Importacao::VALIDADE_DA_TRAVA).to be < 3.hours
  end

  it 'a base com limpeza pendente entra só para limpar, sem baixar de novo' do
    ligar
    %w[queimadas planos_de_saude aeronaves].each { |base| estado.create!(base: base, geracao_ativa: 1, atualizado_em: 1.hour.ago) }
    estado.create!(base: 'geracao_solar', geracao_ativa: 2, atualizado_em: 4.hours.ago, linhas: 1, tentado_em: 4.hours.ago,
                   falhou_em: 4.hours.ago, motivo_da_falha: 'limpeza_pendente')
    estado.create!(base: 'transportadoras', geracao_ativa: 1, atualizado_em: 2.days.ago)
    Autonomia::FerramentasProntas::Bases::GeracaoDistribuida.create!(geracao: 1, cep: '78890000', tipo: 'solar', quantidade: 1, potencia_kw: 1)
    Autonomia::FerramentasProntas::Bases::GeracaoDistribuida.create!(geracao: 2, cep: '78890000', tipo: 'solar', quantidade: 2, potencia_kw: 2)

    described_class.perform_now
    expect(enfileiradas).to eq(['geracao_solar'])

    fila.perform_now('geracao_solar')

    expect(Autonomia::FerramentasProntas::Bases::GeracaoDistribuida.pluck(:geracao)).to eq([2])
    expect(estado.find_by(base: 'geracao_solar')).to have_attributes(geracao_ativa: 2, motivo_da_falha: nil)
    expect(a_request(:get, Autonomia::FerramentasProntas::Bases::GeracaoSolar::ARQUIVO)).not_to have_been_made
  end

  it 'antes do horário da stack, nada; o horário vem do ENV, e sem ele cada stack tem o seu (pelo endereço)' do
    ligar
    with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: '11:30') { described_class.perform_now }
    expect(enfileiradas).to be_empty

    with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: nil, FRONTEND_URL: 'https://app.um.exemplo.test') do
      um = described_class.horario
      outro = with_modified_env(FRONTEND_URL: 'https://app.dois.exemplo.test') { described_class.horario }
      expect([um, outro]).to all(be_between(10 * 60, (11 * 60) + 55))
      expect(um).not_to eq(outro)
    end
  end

  it 'compara o horário em minutos: "9:05" vale 09:05 (antes das 10:47 entra)' do
    ligar
    with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: '9:05') { described_class.perform_now }

    expect(enfileiradas).to eq(['queimadas'])
  end

  it 'horário inválido: alerta uma vez (log e Sentry) e cai no horário da stack' do
    sentry = stub_const('Sentry', Class.new { def self.capture_message(*, **) = nil })
    allow(sentry).to receive(:capture_message)
    allow(Rails.logger).to receive(:warn).and_call_original
    padrao = with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: nil) { described_class.horario }

    %w[25:00 10:60 10h47 abc 10:4x].each do |invalido|
      valor = with_modified_env(AUTONOMIA_PRONTAS_BASES_HORARIO_UTC: invalido, SENTRY_DSN: 'https://chave@sentry.exemplo.test/1') do
        Array.new(2) { described_class.horario }
      end
      expect(valor).to eq([padrao, padrao])
    end
    expect(Rails.logger).to have_received(:warn).with(include('ALERTA horario_invalido')).once
    expect(sentry).to have_received(:capture_message).once
  ensure
    Redis::Alfred.delete(described_class::ALERTA_DO_HORARIO)
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
