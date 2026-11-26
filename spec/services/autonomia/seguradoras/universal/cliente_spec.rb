require 'rails_helper'

RSpec.describe Autonomia::Seguradoras::Universal::Cliente do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:cliente) { described_class.new(login: 'corretor.teste', senha: 's3nha-teste') }

  it 'manda Login e Senha nos cabeçalhos' do
    stub = stub_request(:get, "#{base}/v1/Emissor/Setup")
           .with(headers: { 'Login' => 'corretor.teste', 'Senha' => 's3nha-teste', 'Accept' => 'application/json' })
           .to_return(status: 200, body: file_fixture('../universal/setup.json').read)
    cliente.setup
    expect(stub).to have_been_requested
  end

  it '401 vira acesso_recusado' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401, body: '')
    expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('acesso_recusado') }
  end

  it '400 vira pedido_invalido com a mensagem curta da seguradora' do
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 400, body: file_fixture('../universal/compras_400.json').read)
    expect { cliente.comprar({}) }.to raise_error(described_class::Erro) { |e|
      expect(e.codigo).to eq('pedido_invalido')
      expect(e.mensagem_da_seguradora).to eq('Valor enviado no cartão é incompatível com a tarifa do produto')
    }
  end

  it '403 vira acesso_recusado' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 403, body: '')
    expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('acesso_recusado') }
  end

  [404, 409, 422].each do |status|
    it "#{status} vira pedido_invalido" do
      stub_request(:post, "#{base}/v1/Cotacao").to_return(status: status, body: '{"message":"curta"}')
      expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e|
        expect(e.codigo).to eq('pedido_invalido')
        expect(e.mensagem_da_seguradora).to eq('curta')
      }
    end
  end

  it '4xx com corpo que não é JSON vira pedido_invalido sem mensagem' do
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 400, body: '<html>ruim</html>')
    expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e|
      expect(e.codigo).to eq('pedido_invalido')
      expect(e.mensagem_da_seguradora).to be_nil
    }
  end

  it 'queda de conexão vira indisponivel e é registrada sem a mensagem da exceção' do
    saida = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(saida))
    stub_request(:post, "#{base}/v1/Cotacao").to_raise(Errno::ECONNRESET)
    expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
    expect(saida.string).to include('chamada=cotar status=sem_resposta')
  end

  it 'host ou rede inalcançável, conexão que esgota e IO cortado viram indisponivel (nunca 500 na conferência)' do
    [Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT, IOError].each do |falha|
      stub_request(:get, "#{base}/v1/Emissor/Setup").to_raise(falha)
      expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
    end
  end

  it 'o emissor é um resumo do login, igual para o mesmo login e sem o login dentro' do
    outro = described_class.new(login: 'outro.corretor.teste', senha: 's3nha-teste')
    expect(cliente.emissor).to eq(described_class.new(login: 'corretor.teste', senha: 'outra').emissor)
    expect(cliente.emissor).not_to eq(outro.emissor)
    expect(cliente.emissor).not_to include('corretor')
  end

  it '500 vira indisponivel' do
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 500, body: 'erro')
    expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
  end

  it 'JSON inválido em 200 vira indisponivel' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: '<html>')
    expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
  end

  it 'timeout vira indisponivel' do
    stub_request(:post, "#{base}/v1/Cotacao").to_timeout
    expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
  end

  # #3211: o Setup roda dentro da requisição da tela (Rack::Timeout de 15 s): abertura + leitura até 12 s, sem repetir.
  it 'Setup cabe no prazo da tela: abertura + leitura até 12 s e sem repetição do GET' do
    capturado = nil
    allow(Net::HTTP).to(receive(:new).and_wrap_original { |original, *args| capturado = original.call(*args) })
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: file_fixture('../universal/setup.json').read)

    cliente.setup

    expect(capturado.open_timeout + capturado.read_timeout).to be <= 12
    expect(capturado.max_retries).to eq(0)
  end

  it 'timeout no Setup vira indisponivel' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_timeout
    expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
  end

  it 'cotar manda o pedido como JSON e devolve o corpo' do
    stub = stub_request(:post, "#{base}/v1/Cotacao")
           .with(body: { 'a' => 1 }.to_json, headers: { 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: file_fixture('../universal/cotacao.json').read)
    expect(cliente.cotar('a' => 1)).to eq(JSON.parse(file_fixture('../universal/cotacao.json').read))
    expect(stub).to have_been_requested
  end

  it 'URL base pela ENV' do
    with_modified_env(UNIVERSAL_API_BASE_URL: 'https://universal.exemplo.test') do
      stub = stub_request(:get, 'https://universal.exemplo.test/v1/destinos').to_return(status: 200, body: '[]')
      cliente.destinos
      expect(stub).to have_been_requested
    end
  end

  # #3246: o pagamento e o voucher pelo carrinho da proposta. Respostas com dados fictícios.
  describe 'status_do_pagamento e url_do_voucher' do
    let(:status_pago) do
      { 'idCarrinhoCompra' => 987_654, 'statusVoucher' => 'Ativo', 'statusPagamento' => 'Pago', 'formaPagamento' => 2,
        'dataPagamento' => '2026-11-26T11:47:40' }
    end

    it 'status do pagamento: GET com o carrinho no caminho, e devolve o corpo' do
      stub = stub_request(:get, "#{base}/v1/StatusPagamento/987654")
             .with(headers: { 'Login' => 'corretor.teste', 'Senha' => 's3nha-teste' })
             .to_return(status: 200, body: status_pago.to_json)
      expect(cliente.status_do_pagamento(987_654)).to eq(status_pago)
      expect(stub).to have_been_requested
    end

    it 'url do voucher: GET pelo carrinho, em português, impressão b' do
      corpo = { 'url' => 'https://voucher.exemplo.test/PrintVoucher/?numeroCarrinho=dGVzdGU=&idioma=portugues' }
      stub = stub_request(:get, "#{base}/v1/Voucher/imprimir/987654")
             .with(query: { 'tipoParametro' => 'idCarrinho', 'tipoImpressao' => 'b', 'idioma' => 'portugues' })
             .to_return(status: 200, body: corpo.to_json)
      expect(cliente.url_do_voucher('987654')).to eq(corpo)
      expect(stub).to have_been_requested
    end

    it 'carrinho que não é inteiro positivo só de dígitos é recusado antes de qualquer chamada' do
      ['', nil, '0', '-5', '12a', '12/../x', '١٢', ' 12', 12.5, 0].each do |carrinho|
        expect { cliente.status_do_pagamento(carrinho) }
          .to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('pedido_invalido') }
        expect { cliente.url_do_voucher(carrinho) }
          .to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('pedido_invalido') }
      end
      expect(a_request(:get, ->(uri) { uri.host == 'api-br.universal-assistance.com' })).not_to have_been_made
    end

    it 'carrinho inexistente (500) vira indisponivel' do
      stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 500, body: '')
      expect { cliente.status_do_pagamento(987_654) }
        .to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
    end

    it 'voucher não encontrado (400 com texto puro) vira pedido_invalido sem mensagem' do
      stub_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))
                                                              .to_return(status: 400, body: '"Voucher não encontrado."')
      expect { cliente.url_do_voucher(987_654) }.to raise_error(described_class::Erro) { |e|
        expect(e.codigo).to eq('pedido_invalido')
        expect(e.mensagem_da_seguradora).to be_nil
      }
    end

    it 'leitura de até 15 s, sem repetição do GET' do
      capturado = nil
      allow(Net::HTTP).to(receive(:new).and_wrap_original { |original, *args| capturado = original.call(*args) })
      stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 200, body: status_pago.to_json)
      cliente.status_do_pagamento(987_654)
      expect([capturado.read_timeout, capturado.max_retries]).to eq([15, 0])
    end
  end

  # #3249: o catálogo de coberturas, sem preço, guardado por um dia por emissor e tipo de viagem.
  describe 'beneficios' do
    let(:catalogo) { file_fixture('../universal/beneficios_internacional.json').read }

    around do |exemplo|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      begin
        exemplo.run
      ensure
        Rails.cache = original
      end
    end

    def stub_beneficios(nacional, status: 200, corpo: catalogo)
      stub_request(:get, "#{base}/v1/beneficios")
        .with(query: { 'idioma' => 'portugues', 'tipoTarifa' => '1', 'nacional' => nacional.to_s },
              headers: { 'Login' => 'corretor.teste', 'Senha' => 's3nha-teste' })
        .to_return(status: status, body: corpo)
    end

    it 'GET em português, tarifa 1, com o tipo de viagem, e devolve o corpo' do
      stub = stub_beneficios(false)
      expect(cliente.beneficios(nacional: false)).to eq(JSON.parse(catalogo))
      expect(stub).to have_been_requested
    end

    it 'leitura de até 15 s, sem repetição do GET' do
      capturado = nil
      allow(Net::HTTP).to(receive(:new).and_wrap_original { |original, *args| capturado = original.call(*args) })
      stub_beneficios(false)
      cliente.beneficios(nacional: false)
      expect([capturado.read_timeout, capturado.max_retries]).to eq([15, 0])
    end

    it 'a segunda chamada vem do cache, separado por nacional e internacional' do
      internacional = stub_beneficios(false)
      nacional = stub_beneficios(true, corpo: file_fixture('../universal/beneficios_nacional.json').read)
      2.times { cliente.beneficios(nacional: false) }
      2.times { cliente.beneficios(nacional: true) }
      expect(internacional).to have_been_requested.once
      expect(nacional).to have_been_requested.once
    end

    it 'o cache é por emissor, e a chave não leva login nem senha' do
      stub = stub_beneficios(false)
      outro = described_class.new(login: 'outro.corretor.teste', senha: 's3nha-teste')
      allow(Rails.cache).to receive(:fetch).and_call_original

      [cliente, outro, cliente].each { |quem| quem.beneficios(nacional: false) }

      expect(stub).to have_been_requested.twice
      expect(Rails.cache).to have_received(:fetch).with(a_string_including(cliente.emissor), anything).twice
      expect(Rails.cache).not_to have_received(:fetch).with(a_string_including('corretor.teste'), anything)
      expect(Rails.cache).not_to have_received(:fetch).with(a_string_including('s3nha-teste'), anything)
    end

    it 'a falha levanta e não fica no cache' do
      stub_beneficios(false, status: 500, corpo: '')
      expect { cliente.beneficios(nacional: false) }
        .to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
      stub = stub_beneficios(false)
      expect(cliente.beneficios(nacional: false)).to eq(JSON.parse(catalogo))
      expect(stub).to have_been_requested.once
    end

    it 'catálogo sem plano conta como falha (indisponivel) e não fica no cache' do
      stub_beneficios(false, corpo: { 'beneficios' => [], 'produtos' => [] }.to_json)
      expect { cliente.beneficios(nacional: false) }
        .to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
      stub_beneficios(false)
      expect(cliente.beneficios(nacional: false)).to eq(JSON.parse(catalogo))
    end
  end

  it 'log sem credencial, sem corpo, sem dado pessoal (R2/R5)' do
    saida = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(saida))
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 400, body: file_fixture('../universal/compras_400.json').read)
    begin
      cliente.comprar('DadosTitular' => { 'Documento' => '52998224725', 'Nome' => 'Fulano' })
    rescue described_class::Erro
      nil
    end
    expect(saida.string).to include('chamada=comprar status=400')
    expect(saida.string).not_to include('corretor.teste', 's3nha-teste', '52998224725', 'Fulano', 'incompatível')
  end
end
