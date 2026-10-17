require 'rails_helper'

# Teto global de desenhos da imagem de prévia (#1303): no máximo `limit` blocos rodando ao mesmo tempo, e um por conta;
# vaga que não vaza (solta ao terminar e em erro, expira sozinha se o processo morrer) e que só o dono solta.
RSpec.describe Crm::BookingV2::PreviewImage::DrawLimit do
  let(:slot_keys) { Array.new(described_class::MAX_LIMIT) { |index| described_class.slot_key(index) } }
  let(:accounts) { [101, 202, 303, 404] }

  def clear_slots
    (slot_keys + accounts.map { |id| described_class.account_key(id) }).each { |key| Redis::Alfred.delete(key) }
  end

  def taken
    slot_keys.count { |key| Redis::Alfred.exists?(key) }
  end

  # Ocupa as vagas como outro processo ocuparia. `millis`: prazo em milissegundos.
  def occupy(count, owner: 'outro-processo', millis: 30_000)
    count.times do |index|
      Redis::Alfred.set(described_class.slot_key(index), owner, nx: true)
      Redis::Alfred.with { |conn| conn.pexpire(described_class.slot_key(index), millis) }
    end
  end

  # No teste, cada conexão do pool `$alfred` é um MockRedis com dados próprios (config/initializers/01_redis.rb). Com
  # threads, uma pegava a vaga numa conexão e soltava em outra, e o teto deixava de ser um só. Um pool de UMA conexão
  # faz o papel do Redis de verdade: um banco só, um comando por vez.
  around do |example|
    original = $alfred # rubocop:disable Style/GlobalVars
    $alfred = ConnectionPool.new(size: 1, timeout: 5) { Redis::Namespace.new('alfred', redis: MockRedis.new) } # rubocop:disable Style/GlobalVars
    example.run
  ensure
    $alfred = original # rubocop:disable Style/GlobalVars
  end

  before { clear_slots }
  after { clear_slots }

  describe '.limit' do
    it 'é 2 por padrão e aceita ajuste pela variável de ambiente' do
      expect(described_class.limit).to eq(2)
      with_modified_env('CRM_BOOKING_PREVIEW_MAX_DRAWS' => '5') { expect(described_class.limit).to eq(5) }
    end

    it 'volta ao padrão com valor inválido, zero ou negativo, e nunca passa do máximo' do
      ['abc', '', '0', '-3', '2.5'].each do |value|
        with_modified_env('CRM_BOOKING_PREVIEW_MAX_DRAWS' => value) { expect(described_class.limit).to eq(2), "aceitou #{value.inspect}" }
      end
      with_modified_env('CRM_BOOKING_PREVIEW_MAX_DRAWS' => '999') { expect(described_class.limit).to eq(described_class::MAX_LIMIT) }
    end
  end

  describe '.with_slot' do
    it 'roda o bloco segurando uma vaga e a da conta, devolve o resultado e solta as duas ao terminar' do
      result = described_class.with_slot(101) do
        expect(taken).to eq(1)
        expect(Redis::Alfred.exists?(described_class.account_key(101))).to be(true)
        :desenhado
      end

      expect(result).to eq(:desenhado)
      expect(taken).to eq(0)
      expect(Redis::Alfred.exists?(described_class.account_key(101))).to be(false)
    end

    it 'cheio: levanta Full sem rodar o bloco, devolve a vaga da conta e não mexe nas vagas dos outros' do
      occupy(2)
      ran = false

      expect { described_class.with_slot(101) { ran = true } }.to raise_error(described_class::Full)

      expect(ran).to be(false)
      expect(taken).to eq(2)
      expect(Redis::Alfred.get(described_class.slot_key(0))).to eq('outro-processo')
      expect(Redis::Alfred.exists?(described_class.account_key(101))).to be(false)
    end

    it 'usa a vaga que sobrou quando só uma está ocupada' do
      occupy(1)

      expect(described_class.with_slot(101) { taken }).to eq(2)
      expect(taken).to eq(1)
    end

    it 'uma conta só desenha uma imagem por vez: a segunda espera, e outra conta usa a vaga livre' do
      described_class.with_slot(101) do
        expect { described_class.with_slot(101) { nil } }.to raise_error(described_class::Full)
        expect(described_class.with_slot(202) { taken }).to eq(2)
      end
    end

    it 'solta as vagas quando o bloco levanta erro, inclusive LoadError' do
      [StandardError.new('quebrou'), LoadError.new('sem libvips')].each do |failure|
        expect { described_class.with_slot(101) { raise failure } }.to raise_error(failure.class)
        expect(taken).to eq(0)
        expect(Redis::Alfred.exists?(described_class.account_key(101))).to be(false)
      end
    end

    it 'as vagas têm prazo: maior que a trava por página e no máximo SLOT_SECONDS' do
      described_class.with_slot(101) do
        [described_class.slot_key(0), described_class.account_key(101)].each do |key|
          expect(Redis::Alfred.ttl(key)).to be_between(Crm::BookingV2::PreviewImage::Store::LOCK_SECONDS + 1, described_class::SLOT_SECONDS)
        end
      end
    end

    it 'vaga de processo que morreu some quando o prazo vence, sem ninguém soltar' do
      occupy(2)
      expect { described_class.with_slot(101) { nil } }.to raise_error(described_class::Full)

      2.times { |index| Redis::Alfred.with { |conn| conn.pexpire(described_class.slot_key(index), 1) } }
      sleep 0.05

      expect(described_class.with_slot(101) { :livre }).to eq(:livre)
    end

    it 'erro do Redis depois de pegar a vaga da conta: devolve a da conta e deixa o erro subir' do
      allow(Redis::Alfred).to receive(:set).and_call_original
      allow(Redis::Alfred).to receive(:set).with(described_class.slot_key(0), anything, nx: true, ex: described_class::SLOT_SECONDS)
                                           .and_raise(Redis::CannotConnectError, 'sem Redis')

      expect { described_class.with_slot(101) { nil } }.to raise_error(Redis::CannotConnectError)

      expect(Redis::Alfred.exists?(described_class.account_key(101))).to be(false)
    end

    it 'não solta a vaga de outro dono quando a própria expirou no meio do desenho' do
      described_class.with_slot(101) do
        key = described_class.slot_key(0)
        Redis::Alfred.delete(key)
        Redis::Alfred.set(key, 'outro-processo', nx: true, ex: 30)
      end

      expect(Redis::Alfred.get(described_class.slot_key(0))).to eq('outro-processo')
    end

    it 'respeita o limite ajustado' do
      with_modified_env('CRM_BOOKING_PREVIEW_MAX_DRAWS' => '3') do
        occupy(3)
        expect { described_class.with_slot(101) { nil } }.to raise_error(described_class::Full)
      end
    end

    # Os dois que pegam vaga esperam um pelo outro dentro do bloco: os dois estão desenhando ao mesmo tempo, sem
    # depender de quanto tempo cada thread leva para começar.
    it 'com vários pedidos ao mesmo tempo, de contas diferentes, nunca passa do limite' do
      inside = Concurrent::CountDownLatch.new(2)
      done = Concurrent::CountDownLatch.new(1)
      running = Concurrent::AtomicFixnum.new(0)
      peak = Concurrent::AtomicFixnum.new(0)

      threads = accounts.flat_map { |account| [account, account] }.map do |account|
        Thread.new do
          described_class.with_slot(account) do
            now = running.increment
            peak.update { |seen| [seen, now].max }
            inside.count_down
            done.wait(5)
            running.decrement
            :desenhou
          end
        rescue described_class::Full
          :cheio
        end
      end

      expect(inside.wait(5)).to be(true)
      Timeout.timeout(5) { sleep 0.05 until threads.count(&:alive?) == 2 }
      done.count_down
      outcomes = threads.map(&:value)

      expect(peak.value).to eq(2)
      expect(outcomes.tally).to eq({ desenhou: 2, cheio: 6 })
      expect(taken).to eq(0)
    end
  end
end
