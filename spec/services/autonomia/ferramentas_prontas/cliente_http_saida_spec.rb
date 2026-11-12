require 'rails_helper'

# #2942: o cliente HTTP das prontas sai pelo IP próprio da conta (Webshare), o teto conta por esse IP, e 429/403 vão à
# telemetria por IP e host (com quarentena quando repetem). A rede e a Webshare são dubladas.
RSpec.describe Autonomia::FerramentasProntas::ClienteHttp do
  let(:account) { create(:account) }
  let(:outra) { create(:account) }
  let(:teto) { Autonomia::FerramentasProntas::TetoDoProvedor }
  let(:cep) { 'https://brasilapi.com.br/api/cep/v2/01001000' }
  # Por onde cada pedido saiu: o IP próprio, ou nil (o IP do servidor).
  let(:saiu_por) { [] }

  around do |example|
    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: '203.0.113.11,203.0.113.12',
                      WEBSHARE_RESERVED_PROXY_ADDRESSES: '203.0.113.11,203.0.113.12') { example.run }
  end

  before do
    resolver_hosts_das_prontas
    zerar_saida_das_prontas
    ligar_ip_proprio(account)
    allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, url, **opcoes, &bloco|
      saiu_por << opcoes[:proxy]&.address
      original.call(url, **opcoes, &bloco)
    end
  end

  def cliente(conta = account)
    described_class.new(hosts: %w[brasilapi.com.br], prazo_final: described_class.agora + 5, conta: conta.id)
  end

  def motivo_de
    yield
    nil
  rescue Autonomia::FerramentasProntas::Provedor::Falha => e
    e.motivo
  end

  def recusas_do_dia
    Redis::Alfred.with { |conn| conn.hgetall("#{Autonomia::FerramentasProntas::Saida::Recusas::CHAVE}:#{Time.current.utc.to_date.iso8601}") }
  end

  it 'com a flag, a consulta sai pelo IP proprio da conta; sem ela, pelo IP do servidor' do
    webshare_datacenter([proxy_da_webshare(11, '203.0.113.11')])
    fonte_responde(cep, { city: 'São Paulo' })

    expect(cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)).to eq('city' => 'São Paulo')
    expect(cliente(outra).get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)).to eq('city' => 'São Paulo')
    expect(saiu_por).to eq(['203.0.113.11', nil])
  end

  it 'a Webshare fora: a consulta sai pelo IP do servidor (decisao do Rodrigo, 12/11) e responde' do
    webshare_datacenter_fora
    fonte_responde(cep, { city: 'São Paulo' })

    expect(cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)).to eq('city' => 'São Paulo')
    expect(saiu_por).to eq([nil])
  end

  it 'com IP proprio, o teto do host vale inteiro naquele IP e nao gasta a cota do IP do servidor' do
    photon = 'photon.komoot.io'

    60.times { expect(teto.reservar!(photon, conta: account.id, saida: '203.0.113.11')).to be(true) }

    expect(teto.reservar!(photon, conta: account.id, saida: '203.0.113.11')).to be(false)
    expect(teto.reservar!(photon, conta: outra.id, saida: '203.0.113.12')).to be(true)
    15.times { expect(teto.reservar!(photon, conta: account.id)).to be(true) } # a fatia do IP do servidor segue intacta
  end

  it '429 repetidos do mesmo host no IP proprio poem o IP de molho, e a conta ganha outro' do
    webshare_datacenter([proxy_da_webshare(11, '203.0.113.11'), proxy_da_webshare(12, '203.0.113.12')])
    fonte_fora(cep, status: 429)

    3.times { expect(motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('limite_da_fonte') }

    expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.sole)
      .to have_attributes(proxy_address: '203.0.113.11', reason: 'brasilapi.com.br 429')
    expect(recusas_do_dia).to eq('203.0.113.11|brasilapi.com.br|429' => '3')
    motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }
    expect(saiu_por.last).to eq('203.0.113.12')
  end

  it '403 pelo IP do servidor vai a telemetria, sem quarentena' do
    fonte_fora(cep, status: 403)

    expect(motivo_de { cliente(outra).get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('pedido_recusado')
    expect(recusas_do_dia).to eq('servidor|brasilapi.com.br|403' => '1')
    expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.count).to eq(0)
  end

  it 'o proxy que recusa o tunel falha com falha_do_proxy e a lista da Webshare e relida (a credencial pode ter mudado)' do
    webshare = webshare_datacenter([proxy_da_webshare(11, '203.0.113.11')])
    allow(SafeFetch).to receive(:fetch).and_raise(Net::HTTPClientException.new('407 Proxy Authentication Required', nil))

    expect(motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('falha_do_proxy')
    motivo_de { cliente.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }
    expect(webshare).to have_received(:proxies).twice
  end
end
