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
