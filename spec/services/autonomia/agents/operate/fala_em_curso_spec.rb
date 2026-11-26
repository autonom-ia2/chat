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

  # #3235: o fim é agora mais a duração real da entrega, não uma estimativa pelo tamanho do texto.
  it 'fim previsto: agora mais a duração dada, gravado com o turno', :aggregate_failures do
    fim = fala.prever_fim!(42, 7, 38_000)
    expect(fim).to eq(38.seconds.from_now)
    expect(fala.fim_previsto(42)).to be_within(0.001.seconds).of(fim)
    expect(Redis::Alfred.get(fala.chave_do_fim(42))).to eq("7:#{(fim.to_f * 1000).round}")
  end

  # #3211 (revisão final F4): a cadeia que para antes do 1º pedaço apaga o fim do seu turno, e só o dele.
  it 'esquecer o fim apaga só o fim do próprio turno', :aggregate_failures do
    fala.prever_fim!(42, 7, 1000)

    expect(fala.esquecer_o_fim(42, 8)).to be(false)
    expect(fala.fim_previsto(42)).to be_present

    expect(fala.esquecer_o_fim(42, 7)).to be(true)
    expect(fala.fim_previsto(42)).to be_nil
  end

  it 'esquecer o fim sem fim gravado ou sem id: nada' do
    expect(fala.esquecer_o_fim(42, 7)).to be(false)
    expect(fala.esquecer_o_fim(42, nil)).to be(false)
  end

  it 'fim previsto tem teto de 150 s' do
    expect(fala.prever_fim!(42, 7, 400_000)).to eq(150.seconds.from_now)
  end

  # Pega: a duração da fala sair do agendamento (o job prende cada espera entre 0,1 s e 30 s; a soma tem de prender igual).
  it 'a duração da cadeia é a soma das esperas dos pedaços, presas como o job as prende', :aggregate_failures do
    pedacos = [{ 'delay_ms' => 5000 }, { 'delay_ms' => 6000 }, { 'delay_ms' => 45_000 }, { 'delay_ms' => 20 }, {}]

    expect(fala.duracao_da_cadeia_ms(pedacos)).to eq(5000 + 6000 + 30_000 + 100 + 100)
    expect(fala.espera_do_pedaco({ 'delay_ms' => 45_000 })).to eq(30.0)
    expect(fala.duracao_da_cadeia_ms([])).to eq(0)
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
    expect(fala.prever_fim!(42, 7, 1000)).to be_nil
  end

  # O pool do Redis (ConnectionPool, espera de 1 s) esgotado não é Redis::BaseError; o `soltar` roda no ensure de todo
  # ReplyJob e ChunkedDeliveryJob, com ou sem as opções, e não pode levantar.
  it 'tempo de espera do pool no soltar: não levanta' do
    allow(Redis::Alfred).to receive(:delete_if_equals).and_raise(ConnectionPool::TimeoutError)
    expect { fala.soltar(42, 7) }.not_to raise_error
  end

  # Valor gravado antes do turno no valor (só os ms, sem "<id>:"): o fim ainda é lido, e ninguém o apaga como seu.
  it 'fim no formato antigo, só ms: é lido e esquecer_o_fim não o apaga', :aggregate_failures do
    fim = 20.seconds.from_now
    Redis::Alfred.set(fala.chave_do_fim(42), (fim.to_f * 1000).round)

    expect(fala.fim_previsto(42)).to be_within(0.001.seconds).of(fim)
    expect(fala.esquecer_o_fim(42, 7)).to be(false)
    expect(Redis::Alfred.get(fala.chave_do_fim(42))).to eq((fim.to_f * 1000).round.to_s)
  end

  # #3211 (revisão final F3): só a falha do Redis é engolida; erro de código sobe, não vira "ninguém falando".
  it 'erro que não é do Redis sobe', :aggregate_failures do
    allow(Redis::Alfred).to receive(:get).and_raise(NoMethodError)
    allow(Redis::Alfred).to receive(:set).and_raise(NoMethodError)
    expect { fala.ocupada_por_outro?(42, 8) }.to raise_error(NoMethodError)
    expect { fala.ocupar(42, 7) }.to raise_error(NoMethodError)
    expect { fala.fim_previsto(42) }.to raise_error(NoMethodError)
  end
end
