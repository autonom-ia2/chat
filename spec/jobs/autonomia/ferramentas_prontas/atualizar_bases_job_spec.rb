require 'rails_helper'

# #2858 (F5): a rodada diária das bases. Enfileira só a base que passou da hora, e nada sem conta com a flag das bases.
RSpec.describe Autonomia::FerramentasProntas::AtualizarBasesJob do
  include ActiveJob::TestHelper

  let(:estado) { Autonomia::FerramentasProntas::Bases::Estado }
  let(:fila) { Autonomia::FerramentasProntas::AtualizarBaseJob }

  around { |example| travel_to(Time.zone.parse('2026-11-11 10:47 UTC')) { example.run } }

  it 'sem nenhuma conta com a flag das bases, não enfileira nada (nada é baixado)' do
    create(:account)

    expect { described_class.perform_now }.not_to have_enqueued_job(fila)
  end

  it 'enfileira a nunca baixada, a diária de ontem e a mensal de 28 dias atrás; pula as em dia' do
    create(:account).enable_features!(Autonomia::FerramentasProntas::Bases::FLAG)
    estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: 1.day.ago)
    estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: 2.hours.ago)
    estado.create!(base: 'geracao_solar', geracao_ativa: 1, atualizado_em: 28.days.ago)
    estado.create!(base: 'transportadoras', geracao_ativa: 1, atualizado_em: 27.days.ago)

    described_class.perform_now

    enfileiradas = enqueued_jobs.select { |job| job['job_class'] == fila.name }.map { |job| job['arguments'].first }
    expect(enfileiradas).to contain_exactly('planos_de_saude', 'geracao_solar', 'queimadas')
  end

  it 'a importação de uma base: base que não existe não faz nada' do
    create(:account).enable_features!(Autonomia::FerramentasProntas::Bases::FLAG)
    allow(Autonomia::FerramentasProntas::Bases::Importacao).to receive(:new)

    fila.perform_now('nao_existe')

    expect(Autonomia::FerramentasProntas::Bases::Importacao).not_to have_received(:new)
  end
end
