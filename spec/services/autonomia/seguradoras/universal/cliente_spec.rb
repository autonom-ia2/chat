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

  it 'cotar manda o pedido como JSON e devolve o corpo' do
    stub = stub_request(:post, "#{base}/v1/Cotacao")
           .with(body: { 'a' => 1 }.to_json, headers: { 'Content-Type' => 'application/json' })
           .to_return(status: 200, body: file_fixture('../universal/cotacao.json').read)
    expect(cliente.cotar('a' => 1)).to be_a(Hash).or be_a(Array)
    expect(stub).to have_been_requested
  end

  it 'URL base pela ENV' do
    with_modified_env(UNIVERSAL_API_BASE_URL: 'https://universal.exemplo.test') do
      stub = stub_request(:get, 'https://universal.exemplo.test/v1/destinos').to_return(status: 200, body: '[]')
      cliente.destinos
      expect(stub).to have_been_requested
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
