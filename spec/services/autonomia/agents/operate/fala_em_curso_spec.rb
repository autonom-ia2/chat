require 'rails_helper'

# #3211: quem está falando na conversa e quando a fala termina.
RSpec.describe Autonomia::Agents::Operate::FalaEmCurso do
  subject(:fala) { described_class }

  before do
    freeze_time
    Redis::Alfred.delete(fala.chave_ocupada(42))
    Redis::Alfred.delete(fala.chave_do_fim(42))
  end

  after do
    Redis::Alfred.delete(fala.chave_ocupada(42))
    Redis::Alfred.delete(fala.chave_do_fim(42))
  end

  it 'ocupar e perguntar por outro turno', :aggregate_failures do
    fala.ocupar(42, 7)
    expect(fala.ocupada_por_outro?(42, 8)).to be(true)
    expect(fala.ocupada_por_outro?(42, 7)).to be(false)
    expect(Redis::Alfred.ttl(fala.chave_ocupada(42))).to be > 0
  end

  it 'soltar só apaga a marca do próprio turno', :aggregate_failures do
    fala.ocupar(42, 7)
    fala.soltar(42, 8)
    expect(Redis::Alfred.get(fala.chave_ocupada(42))).to eq('7')
    fala.soltar(42, 7)
    expect(Redis::Alfred.get(fala.chave_ocupada(42))).to be_nil
  end

  it 'soltar com id vazio não faz nada' do
    fala.ocupar(42, 7)
    fala.soltar(42, nil)
    expect(Redis::Alfred.get(fala.chave_ocupada(42))).to eq('7')
  end

  it 'renovar só renova o próprio turno', :aggregate_failures do
    fala.ocupar(42, 7)
    expect(fala.renovar(42, 8)).to be(false)
    expect(fala.renovar(42, 7)).to be(true)
    expect(Redis::Alfred.ttl(fala.chave_ocupada(42))).to be <= Autonomia::Agents::Operate::TurnoEmCurso::TTL_DA_CADEIA.to_i
  end

  it 'sem marca, ninguém ocupa' do
    expect(fala.ocupada_por_outro?(42, 8)).to be(false)
  end

  it 'fim previsto: 160 ms ± 20% por caractere', :aggregate_failures do
    fim = fala.prever_fim!(42, 'a' * 100)
    expect(fim).to be_between(12.8.seconds.from_now, 19.2.seconds.from_now)
    expect(fala.fim_previsto(42)).to be_within(0.001.seconds).of(fim)
  end

  it 'fim previsto tem teto de 150 s' do
    expect(fala.duracao_estimada_ms('a' * 2000)).to eq(150_000)
  end

  it 'sem fim gravado, fim_previsto é nil' do
    expect(fala.fim_previsto(42)).to be_nil
  end

  it 'Redis fora do ar: não levanta, ninguém ocupa, sem fim', :aggregate_failures do
    allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
    expect { fala.ocupar(42, 7) }.not_to raise_error
    expect(fala.ocupada_por_outro?(42, 8)).to be(false)
    expect(fala.fim_previsto(42)).to be_nil
    expect(fala.prever_fim!(42, 'oi')).to be_nil
  end
end
