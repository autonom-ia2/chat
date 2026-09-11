# UM SERVIDOR HTTP MÍNIMO em 127.0.0.1, para os specs que precisam do que o WebMock não emula: TEMPO
# (um corpo que chega devagar, pedaço a pedaço) e o SOCKET (se o cliente fechou a conexão antes de
# ler um corpo). O WebMock, mesmo para a conexão real permitida em localhost, lê a resposta INTEIRA
# antes de entregá-la ao bloco do `Net::HTTP` (`super(request, nil, &nil)` no adapter) — por isso
# quem usa este servidor desliga o WebMock durante o exemplo (`sem_webmock`). O servidor atende UMA
# conexão, lê o pedido, executa o roteiro e conta quantos bytes conseguiu escrever antes de o
# cliente ir embora.
module ServidorHttpLocal
  class Servidor
    attr_reader :bytes_escritos

    def initialize(roteiro)
      @tcp = TCPServer.new('127.0.0.1', 0)
      @bytes_escritos = 0
      @thread = Thread.new { atender(roteiro) }
    end

    def url(caminho)
      "http://127.0.0.1:#{@tcp.addr[1]}#{caminho}"
    end

    # Escreve `dados` no cliente e conta; false quando o cliente já fechou (o roteiro para por aí).
    def escrever(cliente, dados)
      cliente.write(dados)
      @bytes_escritos += dados.bytesize
      true
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError
      false
    end

    def cabecalhos(status, tipo, tamanho)
      "HTTP/1.1 #{status}\r\nContent-Type: #{tipo}\r\nContent-Length: #{tamanho}\r\nConnection: close\r\n\r\n"
    end

    def parar
      @tcp.close unless @tcp.closed?
      @thread.join(5) || @thread.kill
    end

    private

    def atender(roteiro)
      cliente = @tcp.accept
      # O pedido até a linha em branco; o conteúdo dele não interessa a estes specs.
      while (linha = cliente.gets) && linha != "\r\n"; end
      roteiro.call(self, cliente)
    rescue IOError
      nil
    ensure
      cliente&.close
    end
  end

  def servidor_http_local(&roteiro)
    Servidor.new(roteiro)
  end

  # Desliga o WebMock durante o bloco: ligado, a conexão real é lida inteira antes do bloco do
  # `Net::HTTP`, e nem o tempo nem o fechamento do socket seriam observáveis.
  def sem_webmock
    WebMock.disable!
    yield
  ensure
    WebMock.enable!
  end

  def segundos_monotonicos
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

RSpec.configure { |config| config.include ServidorHttpLocal }
