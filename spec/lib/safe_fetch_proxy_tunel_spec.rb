require 'rails_helper'
require 'socket'
require 'io/wait'

# `proxy:` (#2942) com um proxy de verdade: um TCPServer local faz o papel dele. Confere o que chega ao proxy (o túnel
# para o IP que o ssrf_filter conferiu, nunca para o nome), que destino privado nem abre conexão com o proxy, e as
# classes de erro de que o `ClienteHttp` depende para separar "o proxy caiu" de "o site está fora". Sem o WebMock aqui:
# ele substituiria o Net::HTTP, e o túnel não seria testado. Nada sai da máquina (só 127.0.0.1).
RSpec.describe SafeFetch do
  let(:servidor) { TCPServer.new('127.0.0.1', 0) }
  let(:porta) { servidor.addr[1] }
  let(:prazo_do_proxy) { 5 }
  let(:proxy) { SafeFetch::Proxy.new(address: '127.0.0.1', port: porta, user: 'usuario-teste', password: 'senha-teste') }

  around do |example|
    WebMock.disable!
    example.run
  ensure
    WebMock.enable!
    servidor.close unless servidor.closed?
  end

  # O proxy lê o pedido de túnel e responde `status` (sem abrir túnel nenhum). -> as linhas que chegaram. Cada espera tem
  # prazo (`wait_readable`): a CI nunca pendura esperando uma conexão ou uma linha que não vem.
  def proxy_responde(status)
    Thread.new do
      next [] unless servidor.wait_readable(prazo_do_proxy)

      conexao = servidor.accept
      linhas = ler_pedido(conexao)
      conexao.write("HTTP/1.1 #{status}\r\nContent-Length: 0\r\n\r\n")
      conexao.close
      linhas
    end
  end

  def ler_pedido(conexao)
    linhas = []
    while conexao.wait_readable(prazo_do_proxy) && (linha = conexao.gets) && linha != "\r\n"
      linhas << linha.chomp
    end
    linhas
  end

  # -> as linhas que o proxy ouviu; falha (em vez de pendurar) se a thread não terminar no prazo.
  def ouvido(proxy_ouviu)
    terminou = proxy_ouviu.join(prazo_do_proxy)
    raise 'o proxy de teste não terminou no prazo' if terminou.nil?

    terminou.value
  end

  def buscar(ip, por: proxy)
    described_class.fetch('https://brasilapi.com.br/api/cep/v2/01001000', proxy: por, schemes: %w[https], max_retries: 0,
                                                                          resolver: ->(_nome) { [IPAddr.new(ip)] },
                                                                          open_timeout: 2, read_timeout: 2) { |resultado| resultado }
  end

  it 'abre o tunel para o IP conferido (nunca para o nome), com o nome do site no Host e a credencial so para o proxy' do
    proxy_ouviu = proxy_responde('502 Bad Gateway')

    expect { buscar('93.184.216.40') }.to raise_error(Net::HTTPFatalError) { |erro| expect(erro.response.code).to eq('502') }

    linhas = ouvido(proxy_ouviu)
    expect(linhas.first).to eq('CONNECT 93.184.216.40:443 HTTP/1.1')
    expect(linhas).to include('Host: brasilapi.com.br:443', "Proxy-Authorization: Basic #{['usuario-teste:senha-teste'].pack('m0')}")
  end

  it 'o tunel recusado pelo proxy (407) chega como Net::HTTPClientException' do
    proxy_ouviu = proxy_responde('407 Proxy Authentication Required')

    expect { buscar('93.184.216.40') }.to raise_error(Net::HTTPClientException) { |erro| expect(erro.response.code).to eq('407') }
    expect(ouvido(proxy_ouviu).first).to eq('CONNECT 93.184.216.40:443 HTTP/1.1')
  end

  it 'destino privado e recusado antes: nenhuma conexao com o proxy' do
    expect { buscar('10.0.0.5') }.to raise_error(SafeFetch::UnsafeUrlError)
    expect { servidor.accept_nonblock }.to raise_error(IO::WaitReadable)
  end

  it 'proxy fora do ar: FetchError com a causa da ligacao (o ClienteHttp repete pelo servidor)' do
    morto = SafeFetch::Proxy.new(address: '127.0.0.1', port: porta)
    servidor.close

    expect { buscar('93.184.216.40', por: morto) }.to raise_error(SafeFetch::FetchError) { |erro| expect(erro.cause).to be_a(Errno::ECONNREFUSED) }
  end
end
