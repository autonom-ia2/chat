require 'rails_helper'

# config/initializers/01_redis_compartilhado_no_teste.rb (#1718)
# rubocop:disable Style/GlobalVars -- os pools globais são o assunto do spec
RSpec.describe RedisDeTesteSerializado do
  let(:chave) { "spec_1718:#{SecureRandom.hex(6)}" }

  after { Redis::Alfred.delete(chave) }

  # Segura uma conexão numa thread enquanto o bloco roda; assim o bloco, em outra thread,
  # recebe obrigatoriamente outra conexão do pool.
  def segurando_uma_conexao(pool)
    entrou = Queue.new
    sair = Queue.new
    dona = Thread.new do
      pool.with do |conexao|
        entrou << conexao
        sair.pop
      end
    end
    yield entrou.pop
  ensure
    sair << true
    dona.join
  end

  it 'mantém o tamanho, o timeout e o namespace dos pools originais' do
    expect([$alfred.size, $velma.size]).to eq([5, 10])
    expect([$alfred, $velma].map { |pool| pool.instance_variable_get(:@timeout) }).to eq([1, 1])
    expect([$alfred, $velma].map { |pool| pool.with(&:namespace) }).to eq(%w[alfred velma])
  end

  it 'entrega ao Rack::Attack o $velma compartilhado' do
    expect(Rack::Attack.cache.store.redis).to equal($velma)
  end

  it 'faz duas threads, em conexões diferentes, enxergarem o mesmo dado' do
    segurando_uma_conexao($alfred) do |conexao_da_outra_thread|
      conexao_da_outra_thread.set(chave, 'gravado na outra thread')

      $alfred.with do |conexao|
        expect(conexao).not_to equal(conexao_da_outra_thread)
        expect(conexao.get(chave)).to eq('gravado na outra thread')
      end
    end
  end

  it 'compartilha também o $velma entre conexões' do
    segurando_uma_conexao($velma) do |conexao_da_outra_thread|
      conexao_da_outra_thread.set(chave, 'velma')

      expect($velma.with { |conexao| conexao.get(chave) }).to eq('velma')
      conexao_da_outra_thread.del(chave)
    end
  end

  it 'deixa um único vencedor em SET NX disputado por 20 threads' do
    largada = Queue.new
    threads = Array.new(20) do |indice|
      Thread.new do
        largada.pop
        # A pausa mantém as conexões ocupadas ao mesmo tempo, espalhando as threads pelo pool.
        Redis::Alfred.with do |conexao|
          sleep 0.01
          conexao.set(chave, "thread-#{indice}", nx: true, ex: 60)
        end
      end
    end
    20.times { largada << true }
    resultados = threads.map(&:value)

    expect(resultados.count(true)).to eq(1)
    expect(Redis::Alfred.get(chave)).to eq("thread-#{resultados.index(true)}")
  end

  it 'apaga dentro do scan_each sem pular chaves, como o Redis real (#2062)' do
    prefixo = "spec_2062:#{SecureRandom.hex(4)}"
    enchimento = Array.new(150) { |indice| "#{prefixo}:outra:#{indice}" }
    alvos = Array.new(205) { |indice| "#{prefixo}:alvo:#{indice}" }
    (enchimento + alvos).each { |nome| Redis::Alfred.set(nome, 1) }

    Redis::Alfred.scan_each(match: "#{prefixo}:alvo:*") { |nome| Redis::Alfred.delete(nome) }

    expect(Redis::Alfred.keys_count("#{prefixo}:alvo:*")).to eq(0)
    expect(Redis::Alfred.keys_count("#{prefixo}:outra:*")).to eq(150)
  ensure
    enchimento.to_a.each { |nome| Redis::Alfred.delete(nome) }
  end

  it 'faz o delete_if_equals (watch/multi) valer entre threads' do
    segurando_uma_conexao($alfred) do |conexao_da_dona|
      conexao_da_dona.set(chave, 'dona')

      Thread.new { Redis::Alfred.delete_if_equals(chave, 'intrusa') }.join
      expect(conexao_da_dona.get(chave)).to eq('dona')

      Thread.new { Redis::Alfred.delete_if_equals(chave, 'dona') }.join
      expect(conexao_da_dona.get(chave)).to be_nil
    end
  end
end
# rubocop:enable Style/GlobalVars
