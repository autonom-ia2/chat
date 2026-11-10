require 'rails_helper'

# #2858 (F0): a proteção HTTP das ferramentas prontas. Só host do catálogo, sem SSRF, sem seguir redirecionamento para
# fora, com teto de tamanho e prazo total (não só por leitura).
RSpec.describe Autonomia::FerramentasProntas::ClienteHttp do
  let(:hosts) { %w[brasilapi.com.br] }
  let(:cliente) { described_class.new(hosts: hosts, prazo_final: described_class.agora + 5) }

  before { resolver_hosts_das_prontas }

  def motivo_de
    yield
    nil
  rescue Autonomia::FerramentasProntas::Provedor::Falha => e
    e.motivo
  end

  it 'le o JSON de um host do catalogo' do
    fonte_responde('https://brasilapi.com.br/api/cep/v2/01001000', { city: 'São Paulo' })

    expect(cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)).to eq('city' => 'São Paulo')
    expect(cliente.chamadas).to eq(1)
  end

  it 'recusa host fora do catalogo sem fazer pedido' do
    expect(motivo_de { cliente.get_json('fora.exemplo.test', '/x', prazo: 3) }).to eq('host_fora_do_catalogo')
    expect(a_request(:any, /fora\.exemplo\.test/)).not_to have_been_made
  end

  it 'recusa caminho que troca o host (userinfo, sem barra, outra porta)' do
    ['@fora.exemplo.test/x', '.fora.exemplo.test/x', ':8443/x'].each do |caminho|
      expect(motivo_de { cliente.get_json('brasilapi.com.br', caminho, prazo: 3) }).to be_present
    end
    expect(a_request(:any, /fora\.exemplo\.test|:8443/)).not_to have_been_made
  end

  it 'recusa host do catalogo que resolve para IP privado (SSRF)' do
    allow(Resolv).to receive(:getaddresses).with('brasilapi.com.br').and_return(['10.0.0.5'])

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('endereco_recusado')
  end

  it 'nao segue redirecionamento para fora do catalogo' do
    stub_request(:get, 'https://brasilapi.com.br/api/cep/v2/01001000')
      .to_return(status: 302, headers: { 'Location' => 'https://fora.exemplo.test/coleta' })
    fora = stub_request(:any, 'https://fora.exemplo.test/coleta')

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('redirecionou_para_fora')
    expect(fora).not_to have_been_requested
  end

  it 'recusa resposta acima do teto de tamanho' do
    fonte_responde('https://brasilapi.com.br/x', "\"#{'a' * (described_class::MAX_BYTES + 10)}\"")

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/x', prazo: 3) }).to eq('resposta_grande_demais')
  end

  it 'recusa resposta que nao e JSON' do
    fonte_responde('https://brasilapi.com.br/x', '<html>oi</html>', tipo: 'text/html')

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/x', prazo: 3) }).to eq('resposta_invalida')
  end

  it 'traduz o estouro de prazo e o limite da fonte em motivos curtos' do
    fonte_lenta('https://brasilapi.com.br/lenta')
    fonte_fora('https://brasilapi.com.br/muitos', status: 429)

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/lenta', prazo: 3) }).to eq('tempo_esgotado')
    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/muitos', prazo: 3) }).to eq('limite_da_fonte')
  end

  it 'passa ao SafeFetch o prazo TOTAL da chamada, o menor entre o da fonte e o que sobra da consulta' do
    allow(described_class).to receive(:agora).and_return(100.0)
    apertado = described_class.new(hosts: hosts, prazo_final: 101.5)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::TotalTimeoutError, 'prazo')

    motivo_de { apertado.get_json('brasilapi.com.br', '/x', prazo: 3) }

    expect(SafeFetch).to have_received(:fetch).with(
      'https://brasilapi.com.br/x',
      hash_including(total_timeout: 1.5, read_timeout: 1.5, open_timeout: 1.5, cross_origin_redirects: false,
                     allowed_ports: [443], schemes: %w[https], max_bytes: described_class::MAX_BYTES)
    )
  end

  it 'sem prazo restante na consulta, nem chama' do
    vencido = described_class.new(hosts: hosts, prazo_final: described_class.agora - 1)

    expect(motivo_de { vencido.get_json('brasilapi.com.br', '/x', prazo: 3) }).to eq('prazo_total')
    expect(vencido.chamadas).to eq(0)
  end
end
