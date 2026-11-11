# UM SERVIDOR TLS MUDO em 127.0.0.1 (#2906): aceita a conexão, faz o TLS com um certificado próprio para `host`, lê o
# pedido e não responde. É a fonte que demora a mandar os cabeçalhos, o que o WebMock não emula: ele não passa pelo
# laço do `Net::HTTP` que repete o pedido (`transport_request`). Conta as conexões recebidas. Quem usa confia no
# `certificado` (só neste exemplo) e desliga o WebMock (`sem_webmock`).
class ServidorTlsMudo
  attr_reader :porta, :certificado

  def initialize(host)
    @conexoes = Queue.new
    @chave = OpenSSL::PKey::RSA.new(2048)
    @certificado = certificado_para(host)
    @tcp = TCPServer.new('127.0.0.1', 0)
    @porta = @tcp.addr[1]
    @thread = Thread.new { atender }
  end

  def conexoes
    @conexoes.size
  end

  def parar
    @tcp.close unless @tcp.closed?
    @thread.join(2) || @thread.kill
  end

  private

  def atender
    contexto = OpenSSL::SSL::SSLContext.new
    contexto.cert = @certificado
    contexto.key = @chave
    loop do
      tcp = @tcp.accept
      @conexoes << true
      Thread.new(tcp) { |conexao| calar(OpenSSL::SSL::SSLSocket.new(conexao, contexto)) }
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def calar(ssl)
    ssl.accept
    while (linha = ssl.gets) && linha != "\r\n"; end
    ssl.read
  rescue IOError, OpenSSL::SSL::SSLError, SystemCallError
    nil
  ensure
    ssl.close
  end

  def certificado_para(host)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{host}")
    cert.public_key = @chave.public_key
    cert.not_before = 1.hour.ago
    cert.not_after = 1.hour.from_now
    extensoes = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(extensoes.create_extension('subjectAltName', "DNS:#{host}"))
    cert.add_extension(extensoes.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.sign(@chave, OpenSSL::Digest.new('SHA256'))
    cert
  end
end
