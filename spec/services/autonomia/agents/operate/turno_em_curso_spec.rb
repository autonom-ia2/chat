require 'rails_helper'

# #2154: a marca do turno do agente em curso, para a IA de Atribuição não entregar a conversa no meio dele.
RSpec.describe Autonomia::Agents::Operate::TurnoEmCurso do
  let(:conversa) { 987_654 }
  let(:chave) { described_class.chave(conversa) }

  before { Redis::Alfred.delete(chave) }

  it 'o teto do turno sai das configurações e cobre as rodadas da Lia, o debounce e a cadeia', :aggregate_failures do
    runner = Autonomia::Agents::Specialists::Runner
    lia = Autonomia::Insurance::QuoteAgent::Builder::RODADAS_DA_LIA * (runner::SEGUNDOS_DE_FERRAMENTA + runner::SEGUNDOS_POR_CHAMADA)

    expect(described_class.teto_do_turno).to be > lia.seconds
    expect(described_class.teto_do_turno).to be > Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS
  end

  it 'abre com o teto do turno; a mensagem mais nova toma a marca', :aggregate_failures do
    described_class.abrir(conversa, 1)
    expect(Redis::Alfred.ttl(chave)).to be_within(5).of(described_class.teto_do_turno.to_i)

    described_class.abrir(conversa, 2)
    expect(Redis::Alfred.get(chave)).to eq('2')
    expect(described_class.em_curso?(conversa)).to be(true)
  end

  it 'renova só a marca do próprio turno (uma cadeia velha não prolonga nem sobrescreve a nova)', :aggregate_failures do
    described_class.abrir(conversa, 2)

    expect(described_class.renovar(conversa, 1)).to be(false)
    expect(Redis::Alfred.get(chave)).to eq('2')
    expect(Redis::Alfred.ttl(chave)).to be > described_class::TTL_DA_CADEIA.to_i

    expect(described_class.renovar(conversa, 2)).to be(true)
    expect(Redis::Alfred.ttl(chave)).to be_between(1, described_class::TTL_DA_CADEIA.to_i)
  end

  it 'renovar não cria marca que não existe' do
    described_class.renovar(conversa, 1)

    expect(described_class.em_curso?(conversa)).to be(false)
  end

  it 'solta só a marca do próprio turno', :aggregate_failures do
    described_class.abrir(conversa, 2)

    described_class.soltar(conversa, 1)
    expect(described_class.em_curso?(conversa)).to be(true)

    described_class.soltar(conversa, 2)
    expect(described_class.em_curso?(conversa)).to be(false)
  end

  it 'nunca levanta: sem Redis, a entrega segue', :aggregate_failures do
    allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:exists?).and_raise(Redis::CannotConnectError)

    expect(described_class.abrir(conversa, 1)).to be_nil
    expect(described_class.em_curso?(conversa)).to be(false)
  end
end
