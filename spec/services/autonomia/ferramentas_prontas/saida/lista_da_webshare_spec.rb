require 'rails_helper'

# #2942: a lista da Webshare das consultas grátis. Só na memória, por poucos minutos; um cliente por processo (o plano
# resolvido não é pedido de novo); a trava não fica presa durante o HTTP; prazo curto para a Webshare.
RSpec.describe Autonomia::FerramentasProntas::Saida::ListaDaWebshare do
  let(:lista) { [proxy_da_webshare(11, '203.0.113.11')] }

  before { described_class.esquecer! }
  after { described_class.esquecer! }

  it 'guarda a lista por alguns minutos e cria o cliente com o prazo curto' do
    cliente = webshare_datacenter(lista)

    2.times { expect(described_class.proxies).to eq(lista) }

    expect(cliente).to have_received(:proxies).once
    expect(Webshare::Client).to have_received(:new).with(pool: :datacenter, timeout: described_class::PRAZO)
  end

  it 'reusa o mesmo cliente (o plano ja resolvido) a cada busca nova' do
    cliente = webshare_datacenter(lista)

    2.times { described_class.proxies(fresca: true) }

    expect(cliente).to have_received(:proxies).twice
    expect(Webshare::Client).to have_received(:new).once
  end

  it 'a busca nao segura a trava: quem chega espera a busca e fica com o resultado dela' do
    comecou = Queue.new
    pode_responder = Queue.new
    cliente = webshare_datacenter([])
    allow(cliente).to receive(:proxies) do
      comecou << true
      pode_responder.pop
      lista
    end

    primeira = Thread.new { described_class.proxies }
    comecou.pop
    expect(described_class::TRAVA).not_to be_locked
    segunda = Thread.new { described_class.proxies }
    sleep 0.05 until segunda.status == 'sleep'
    pode_responder << :ok

    expect([primeira.value, segunda.value]).to eq([lista, lista])
    expect(cliente).to have_received(:proxies).once
  end

  it 'erro de rede que o cliente nao traduz e lembrado e sobe para a Saida decidir' do
    cliente = webshare_datacenter([])
    allow(cliente).to receive(:proxies).and_raise(Errno::ECONNRESET)

    2.times { expect { described_class.proxies }.to raise_error(Errno::ECONNRESET) }

    expect(cliente).to have_received(:proxies).once
  end

  describe 'o prazo da consulta manda' do
    let(:agora) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    it 'sem lista e sem prazo para a busca caber: nem vai a Webshare (a consulta sai pelo servidor)' do
      cliente = webshare_datacenter(lista)

      expect { described_class.proxies(ate: agora + 0.5) }.to raise_error(Autonomia::FerramentasProntas::Saida::SemTempo)
      expect(cliente).not_to have_received(:proxies)
    end

    it 'com a lista vencida e sem prazo: serve a vencida em vez de esperar a Webshare' do
      cliente = webshare_datacenter(lista)
      described_class.proxies
      depois = agora + described_class::VALIDADE + 1
      allow(described_class).to receive(:agora).and_return(depois)

      expect(described_class.proxies(ate: depois + 0.5)).to eq(lista)
      expect(cliente).to have_received(:proxies).once
    end

    describe 'com a lista vencida e outra busca em andamento' do
      let(:nova) { [proxy_da_webshare(12, '203.0.113.12')] }
      let(:comecou) { Queue.new }
      let(:pode_responder) { Queue.new }

      # A lista vence e outra consulta (sem prazo) começa a buscar a nova, presa até `pode_responder`. Cada espera tem
      # prazo: o teste falha em vez de pendurar. -> [a thread da busca, o instante].
      def vencida_e_buscando
        cliente = webshare_datacenter(lista)
        described_class.proxies
        depois = agora + described_class::VALIDADE + 1
        allow(described_class).to receive(:agora).and_return(depois)
        prender_a_busca(cliente)
        busca = Thread.new { described_class.proxies }
        raise 'a busca nao comecou' if comecou.pop(timeout: 5).nil?

        [busca, depois]
      end

      def prender_a_busca(cliente)
        allow(cliente).to receive(:proxies) do
          comecou << true
          pode_responder.pop
          nova
        end
      end

      def esperando(thread)
        limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.05 until thread.status == 'sleep' || !thread.alive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > limite
        thread
      end

      def valor(thread)
        thread.join(5)&.value || raise('a thread nao terminou no prazo')
      end

      it 'com prazo de sobra, a consulta espera a busca e fica com a lista nova (nunca a vencida)' do
        primeira, depois = vencida_e_buscando
        segunda = esperando(Thread.new { described_class.proxies(ate: depois + 5) })
        pode_responder << :ok

        expect(valor(segunda)).to eq(nova)
        expect(valor(primeira)).to eq(nova)
      end

      it 'a reconciliacao (fresca) nunca recebe a vencida: espera a busca' do
        primeira, = vencida_e_buscando
        reconciliacao = esperando(Thread.new { described_class.proxies(fresca: true) })
        pode_responder << :ok

        expect(valor(reconciliacao)).to eq(nova)
        expect(valor(primeira)).to eq(nova)
      end

      it 'sem prazo para a busca, a consulta fica com a vencida sem esperar' do
        primeira, depois = vencida_e_buscando

        expect(described_class.proxies(ate: depois + 0.1)).to eq(lista)
        pode_responder << :ok
        expect(valor(primeira)).to eq(nova)
      end
    end

    it 'com outra busca em andamento e sem lista: espera so ate o prazo da consulta' do
      comecou = Queue.new
      pode_responder = Queue.new
      cliente = webshare_datacenter([])
      allow(cliente).to receive(:proxies) do
        comecou << true
        pode_responder.pop
        lista
      end
      primeira = Thread.new { described_class.proxies }
      comecou.pop

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.proxies(ate: inicio + 0.3) }.to raise_error(Autonomia::FerramentasProntas::Saida::SemTempo)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 1
      pode_responder << :ok
      expect(primeira.value).to eq(lista)
    end
  end
end
