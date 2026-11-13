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

  it 'o host em que a plataforma entra com o cadastro dela (#2993) nunca sai pelo IP proprio da conta' do
    webshare_datacenter([proxy_da_webshare(11, '203.0.113.11')])
    fonte_responde(cep, { city: 'São Paulo' })
    fonte_responde('https://fora.exemplo.test/veiculo', { achou: true })
    com_cadastro = described_class.new(hosts: %w[brasilapi.com.br fora.exemplo.test], prazo_final: described_class.agora + 5,
                                       conta: account.id)
    com_cadastro.pelo_servidor!('fora.exemplo.test')

    com_cadastro.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)
    com_cadastro.get_json('fora.exemplo.test', '/veiculo', prazo: 3)

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

  describe 'o proxy caiu: repete pelo IP do servidor (decisao do Rodrigo, 12/11)' do
    let(:pelo_proxy) { proxy_da_webshare(11, '203.0.113.11') }

    before do
      webshare_datacenter([pelo_proxy, proxy_da_webshare(12, '203.0.113.12')])
      fonte_responde(cep, { city: 'São Paulo' })
      allow(teto).to receive(:reservar!).and_call_original
    end

    # O pedido pelo proxy levanta o que o bloco levantar; pelo IP do servidor, segue para o WebMock.
    def proxy_falha
      allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, url, **opcoes, &bloco|
        saiu_por << opcoes[:proxy]&.address
        yield if opcoes[:proxy]
        original.call(url, **opcoes, &bloco)
      end
    end

    # Como o SafeFetch levanta: `FetchError`, com a causa da ligação.
    def ligacao_caiu(causa)
      raise causa
    rescue causa.class
      raise SafeFetch::FetchError, 'falhou'
    end

    def tunel(codigo)
      resposta = Net::HTTPResponse::CODE_TO_OBJ.fetch(codigo.to_s).new('1.1', codigo.to_s, 'tunel')
      Net::HTTPResponse::CODE_TO_OBJ.fetch(codigo.to_s).const_get(:EXCEPTION_TYPE).new("#{codigo} tunel", resposta)
    end

    def consultar(com = cliente)
      com.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3)
    end

    it 'ligacao recusada: responde pelo servidor, contando no teto dele, e o resto do cliente nao reusa o proxy' do
      proxy_falha { ligacao_caiu(Errno::ECONNREFUSED.new) }
      mesmo = cliente

      2.times { expect(consultar(mesmo)).to eq('city' => 'São Paulo') }

      expect(saiu_por).to eq(['203.0.113.11', nil, nil])
      expect(teto).to have_received(:reservar!).with('brasilapi.com.br', conta: account.id, saida: '203.0.113.11').once
      expect(teto).to have_received(:reservar!).with('brasilapi.com.br', conta: account.id, saida: nil).twice
      expect(recusas_do_dia).to eq('203.0.113.11|proxy|morto' => '1')
    end

    it 'a queda so conta (e pode trocar o IP) depois de a chamada ja ter repetido pelo servidor' do
      proxy_falha { ligacao_caiu(Errno::ECONNREFUSED.new) }
      chamadas_quando_contou = nil
      allow(Autonomia::FerramentasProntas::Saida::ProxyMorto).to receive(:caiu!).and_wrap_original do |original, *args, **opcoes|
        chamadas_quando_contou = saiu_por.size
        original.call(*args, **opcoes)
      end

      expect(consultar).to eq('city' => 'São Paulo')
      expect(chamadas_quando_contou).to eq(2)
      expect(Autonomia::FerramentasProntas::Saida::ProxyMorto).to have_received(:caiu!)
        .with('203.0.113.11', conta: account.id, ate: kind_of(Float))
    end

    it 'prazo de abertura com o proxy: responde pelo servidor' do
      proxy_falha { ligacao_caiu(Net::OpenTimeout.new) }

      expect(consultar).to eq('city' => 'São Paulo')
      expect(saiu_por).to eq(['203.0.113.11', nil])
    end

    it 'tunel recusado (407): rele a credencial e tenta de novo pelo IP; deu certo, nao conta queda' do
      webshare = webshare_datacenter([pelo_proxy])
      recusou = false
      proxy_falha do
        next if recusou

        recusou = true
        raise tunel(407)
      end

      expect(consultar).to eq('city' => 'São Paulo')
      expect(webshare).to have_received(:proxies).twice
      expect(saiu_por).to eq(['203.0.113.11', '203.0.113.11'])
      expect(recusas_do_dia).to eq({})
    end

    it 'tunel recusado de novo com a lista nova: e o proxy que caiu, e responde pelo servidor' do
      webshare = webshare_datacenter([pelo_proxy])
      proxy_falha { raise tunel(407) }

      expect(consultar).to eq('city' => 'São Paulo')
      expect(webshare).to have_received(:proxies).twice
      expect(saiu_por).to eq(['203.0.113.11', '203.0.113.11', nil])
      expect(recusas_do_dia).to eq('203.0.113.11|proxy|morto' => '1')
    end

    it 'prazo de leitura com o tunel aberto e do site: sem repetir pelo servidor e sem contar contra o IP' do
      proxy_falha { ligacao_caiu(Net::ReadTimeout.new) }
      expect(motivo_de { consultar }).to eq('tempo_esgotado')

      proxy_falha { raise SafeFetch::TotalTimeoutError, 'prazo' }
      expect(motivo_de { consultar }).to eq('tempo_esgotado')

      expect(saiu_por).to eq(['203.0.113.11', '203.0.113.11'])
      expect(recusas_do_dia).to eq({})
    end

    it 'cada sucesso pelo IP zera a contagem de quedas: queda, queda, sucesso, queda nao poe o IP de molho' do
      cair = true
      proxy_falha { ligacao_caiu(Errno::ECONNREFUSED.new) if cair }

      2.times { consultar }
      cair = false
      consultar
      cair = true
      consultar

      expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.count).to eq(0)
      expect(recusas_do_dia).to eq('203.0.113.11|proxy|morto' => '3')
    end

    it 'tunel com 502 ou 504 e o site fora: falha da fonte, sem repetir e sem contar contra o proxy' do
      [502, 504].each do |codigo|
        proxy_falha { raise tunel(codigo) }
        expect(motivo_de { consultar }).to eq('erro_da_fonte')
      end

      expect(saiu_por).to eq(['203.0.113.11', '203.0.113.11'])
      expect(recusas_do_dia).to eq({})
    end

    it 'tres quedas seguidas poem o IP de molho (proxy_morto), e a conta ganha outro' do
      proxy_falha { ligacao_caiu(Errno::EHOSTUNREACH.new) }

      3.times { consultar }
      expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.sole).to have_attributes(proxy_address: '203.0.113.11', reason: 'proxy_morto')
      expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.sole.quarantined_until).to be_within(1.minute).of(24.hours.from_now)

      allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, url, **opcoes, &bloco|
        saiu_por << opcoes[:proxy]&.address
        original.call(url, **opcoes, &bloco)
      end
      consultar
      expect(saiu_por.last).to eq('203.0.113.12')
    end
  end

  it 'o prazo da chamada desconta o tempo gasto achando a saida (que pode ir a Webshare)' do
    allow(Autonomia::FerramentasProntas::Saida).to receive(:para) do
      sleep 0.8
      nil
    end
    devagar = described_class.new(hosts: %w[brasilapi.com.br], prazo_final: described_class.agora + 1, conta: account.id)

    expect(motivo_de { devagar.get_json('brasilapi.com.br', '/api/cep/v2/01001000', prazo: 3) }).to eq('prazo_total')
    expect(saiu_por).to eq([])
  end

  describe 'host que limita pela chave (parallelum e AwesomeAPI com a chave gratuita)' do
    around { |example| with_modified_env(AUTONOMIA_AWESOMEAPI_CHAVE: 'chave-de-teste') { example.run } }

    let(:awesome) { 'cep.awesomeapi.com.br' }

    it 'conta no global e na fatia de antes, mesmo pelo IP proprio: contas com IP proprio nao passam do teto da chave' do
      contas = Array.new(5) { |vez| 1000 + vez }
      contas.first(4).each_with_index do |conta, vez|
        30.times { expect(teto.reservar!(awesome, conta: conta, saida: "203.0.113.#{20 + vez}")).to be(true) }
        expect(teto.reservar!(awesome, conta: conta, saida: "203.0.113.#{20 + vez}")).to be(false)
      end

      expect(teto.reservar!(awesome, conta: contas.last, saida: '203.0.113.30')).to be(false)
    end

    it '429 do host da chave vai a telemetria, sem quarentena (a recusa e da chave, nao do IP)' do
      proxy = SafeFetch::Proxy.new(address: '203.0.113.11', port: 6000)

      3.times { Autonomia::FerramentasProntas::Saida::Recusas.registrar!(host: awesome, status: 429, saida: proxy, conta: account.id) }

      expect(recusas_do_dia).to eq('203.0.113.11|cep.awesomeapi.com.br|429' => '3')
      expect(Autonomia::FerramentasProntas::ProxyEmQuarentena.count).to eq(0)
    end
  end
end
