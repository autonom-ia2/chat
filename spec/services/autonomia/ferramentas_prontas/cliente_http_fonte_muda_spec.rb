require 'rails_helper'

# #2906: uma fonte que aceita a conexão e não responde. O PNCP real a frio fazia isso, e a chamada durava 2x o prazo:
# o `Net::HTTP` repete uma vez o GET depois de um `ReadTimeout` na espera pelos cabeçalhos (`max_retries` padrão 1),
# com conexão nova e o `read_timeout` inteiro de novo. O WebMock não passa por esse laço (`transport_request`), então
# aqui o caminho é o real até o socket: `ClienteHttp` -> `SafeFetch` -> `SsrfFilter` -> `Net::HTTP`, contra um
# servidor TLS em 127.0.0.1 (`ServidorTlsMudo`). Dublados só o DNS (o host vai para o IP público de documentação, como nos outros specs
# das prontas), o destino TCP desse IP (vira a porta local) e a confiança no certificado do servidor de teste.
RSpec.describe Autonomia::FerramentasProntas::ClienteHttp do
  let(:host) { 'pncp.gov.br' }
  let(:prazo) { 1 }
  let(:servidor) { ServidorTlsMudo.new(host) }
  let(:cliente) { described_class.new(hosts: [host], prazo_final: described_class.agora + 10) }

  before do
    resolver_hosts_das_prontas
    ip = FerramentasProntasHelper::HOSTS_DAS_PRONTAS.fetch(host)
    porta = servidor.porta
    allow(TCPSocket).to receive(:open).and_wrap_original do |original, endereco, *resto, **opcoes|
      endereco == ip ? original.call('127.0.0.1', porta, *resto.drop(1), **opcoes) : original.call(endereco, *resto, **opcoes)
    end
    confianca = OpenSSL::X509::Store.new
    confianca.add_cert(servidor.certificado)
    stub_const('OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE', confianca)
  end

  after { servidor.parar }

  it 'desiste no prazo da chamada, numa conexao so, quando a fonte aceita e nao responde', :aggregate_failures do
    inicio = segundos_monotonicos
    motivo = sem_webmock do
      cliente.get_json(host, '/api/consulta/v1/contratacoes/publicacao', prazo: prazo)
      nil
    rescue Autonomia::FerramentasProntas::Provedor::Falha => e
      e.motivo
    end
    decorrido = segundos_monotonicos - inicio

    expect(motivo).to eq('tempo_esgotado')
    expect(servidor.conexoes).to eq(1)
    expect(decorrido).to be < prazo * 1.9
  end
end
