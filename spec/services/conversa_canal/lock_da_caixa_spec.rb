require 'rails_helper'

# #1870 — lock com dono na chave da importação: só solta o que é seu.
RSpec.describe ConversaCanal::LockDaCaixa do
  let(:inbox) { create(:inbox) }
  let(:chave) { described_class.chave(inbox) }

  before { Redis::Alfred.delete(chave) }
  after { Redis::Alfred.delete(chave) }

  it 'usa a mesma chave da importação (EMAIL_MESSAGE_MUTEX)' do
    expect(chave).to eq(format(Redis::Alfred::EMAIL_MESSAGE_MUTEX, inbox_id: inbox.id))
  end

  it 'pega com TTL, roda o bloco e solta no fim' do
    resultado = described_class.com_lock(inbox) do
      expect(Redis::Alfred.ttl(chave)).to be_between(1, described_class::TEMPO.to_i)
      :feito
    end

    expect(resultado).to eq(:feito)
    expect(Redis::Alfred.get(chave)).to be_nil
  end

  it 'lock de outro dono (importação): não pega e não apaga' do
    Redis::Alfred.set(chave, 'lock-da-importacao', ex: 300)

    expect { described_class.com_lock(inbox) { :nunca } }.to raise_error(MutexApplicationJob::LockAcquisitionError)
    expect(Redis::Alfred.get(chave)).to eq('lock-da-importacao')
  end

  it 'passou do TTL e outro dono pegou: no fim não apaga o lock dele' do
    described_class.com_lock(inbox) do
      Redis::Alfred.delete(chave)
      Redis::Alfred.set(chave, 'lock-da-importacao', ex: 300)
    end

    expect(Redis::Alfred.get(chave)).to eq('lock-da-importacao')
  end

  it 'renova o TTL enquanto o lock é nosso' do
    described_class.com_lock(inbox) do |lock|
      Redis::Alfred.expire(chave, 5)
      lock.renovar!

      expect(Redis::Alfred.ttl(chave)).to be > 5
    end
  end

  it 'não renova o lock de outro dono: LockPerdido, e o TTL dele fica' do
    described_class.com_lock(inbox) do |lock|
      Redis::Alfred.set(chave, 'lock-da-importacao', ex: 30)

      expect { lock.renovar! }.to raise_error(described_class::LockPerdido)
      expect(Redis::Alfred.ttl(chave)).to be <= 30
    end
    expect(Redis::Alfred.get(chave)).to eq('lock-da-importacao')
  end

  it 'solta mesmo quando o bloco estoura' do
    expect { described_class.com_lock(inbox) { raise IOError, 'caiu' } }.to raise_error(IOError)
    expect(Redis::Alfred.get(chave)).to be_nil
  end
end
