# O envio do passo "webhook" (G13, #2670): um POST com JSON a outro sistema, pelo SafeFetch, e a resposta dele.
#
# Segurança (o endereço é escrito pelo dono da conta, e o pedido sai do nosso servidor):
# - só https, sem seguir redirecionamento (o 3xx é recusa) e sem usuário e senha no endereço;
# - nada de rede interna: o nome é resolvido UMA vez aqui, todo IP é conferido (privado, loopback, link-local com o
#   metadata, reservado, IPv4 dentro de IPv6) e o SafeFetch conecta só nesses IPs (`resolver:` fixo). Sem segunda
#   resolução não há DNS rebinding, inclusive numa instalação com SAFE_FETCH_ALLOW_PRIVATE_NETWORK;
# - o próprio servidor da plataforma (o host e os IPs de FRONTEND_URL e HELPCENTER_URL) também é recusado: a automação
#   não chama a nossa API por fora (anti-laço; a API tem a porta da ação, com permissão);
# - prazo curto e resposta pequena: o motor não fica preso num sistema lento.
#
# A assinatura segue o formato dos webhooks da plataforma (Webhooks::Trigger): HMAC SHA256 de "timestamp.corpo" com o
# segredo da automação (SegredoDoWebhook). `X-Automacao-Execucao` e `X-Automacao-Passo` deixam o outro sistema
# descartar a repetição de um erro passageiro.
#
# O resultado nunca carrega a URL inteira (pode ter token na query) nem o segredo: só o host, o código, a duração e a
# resposta lida, que o passo usa e não guarda.
class Autonomia::Automacao::EnvioDoWebhook
  ABRIR_EM = 3
  LER_EM = 10
  PRAZO_TOTAL = 15
  RESPOSTA_MAXIMA = 64.kilobytes
  # 0.0.0.0/8 e a faixa compartilhada das operadoras (100.64/10); no IPv6, o "sem endereço" e o NAT64 (64:ff9b::/96).
  RESERVADOS = %w[0.0.0.0/8 100.64.0.0/10 ::/96 ::/128 64:ff9b::/96].map { |faixa| IPAddr.new(faixa) }.freeze
  Resposta = Struct.new(:tipo, :codigo, :host, :ms, :corpo, :motivo, keyword_init: true)

  # Ao salvar: o endereço é https, tem host, não traz usuário e senha nem aponta para IP interno ou para a plataforma.
  # O nome que resolve para rede interna só se descobre na hora de enviar (o DNS muda).
  def self.problema_do_endereco(url)
    uri = URI.parse(url.to_s)
    return 'webhook_so_https' unless uri.is_a?(URI::HTTPS) && uri.host.present?
    return 'webhook_sem_senha_no_endereco' if uri.userinfo.present?

    'webhook_endereco_interno' if interno?(uri.hostname)
  rescue URI::InvalidURIError
    'webhook_so_https'
  end

  def self.interno?(host)
    nome = host.to_s.downcase.delete_suffix('.')
    return true if nome == 'localhost' || nome.end_with?('.localhost', '.internal', '.local')
    return true if hosts_da_plataforma.include?(nome)

    endereco_interno?(IPAddr.new(nome))
  rescue IPAddr::InvalidAddressError
    false
  end

  # O IPv4 escrito dentro de um IPv6 (::ffff:10.0.0.1) é conferido como o IPv4 que ele é.
  def self.endereco_interno?(endereco)
    ip = endereco.ipv4_mapped? ? endereco.native : endereco
    ip.private? || ip.loopback? || ip.link_local? || RESERVADOS.any? { |faixa| faixa.family == ip.family && faixa.include?(ip) }
  end

  def self.hosts_da_plataforma
    [ENV.fetch('FRONTEND_URL', nil), ENV.fetch('HELPCENTER_URL', nil)].compact_blank.filter_map do |url|
      URI.parse(url).hostname&.downcase
    rescue URI::InvalidURIError
      nil
    end
  end

  # Os IPs da própria plataforma, para o nome de fora que aponta para ela (outro apelido, o IP público).
  def self.ips_da_plataforma = hosts_da_plataforma.flat_map { |host| Resolv.getaddresses(host) }

  def initialize(url:, corpo:, segredo:, execucao_id:, passo_id:)
    @url = url.to_s
    @corpo = corpo.to_json
    @segredo = segredo
    @execucao_id = execucao_id
    @passo_id = passo_id
    @host = host_de(@url)
  end

  def enviar
    motivo = self.class.problema_do_endereco(@url)
    return resposta(:recusado_aqui, motivo: motivo) if motivo

    ips = Resolv.getaddresses(@host.to_s)
    return resposta(:sem_resposta) if ips.empty?
    return resposta(:recusado_aqui, motivo: 'webhook_endereco_interno') if algum_interno?(ips)

    postar(ips)
  end

  private

  def host_de(url)
    URI.parse(url).hostname
  rescue URI::InvalidURIError
    nil
  end

  def algum_interno?(ips)
    da_plataforma = self.class.ips_da_plataforma
    ips.any? { |ip| da_plataforma.include?(ip) || self.class.endereco_interno?(IPAddr.new(ip)) }
  rescue IPAddr::InvalidAddressError
    true
  end

  # Conecta só nos IPs já conferidos: o SafeFetch não resolve o nome de novo.
  def postar(ips)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    conferidos = ips.map { |ip| IPAddr.new(ip) }
    lido = SafeFetch.fetch(@url, method: :post, body: @corpo, headers: cabecalhos, schemes: %w[https], max_redirects: 0,
                                 resolver: ->(_nome) { conferidos }, open_timeout: ABRIR_EM, read_timeout: LER_EM, total_timeout: PRAZO_TOTAL,
                                 max_bytes: RESPOSTA_MAXIMA, error_body_bytes: RESPOSTA_MAXIMA, validate_content_type: false) do |resultado|
      resultado.tempfile.read
    end
    resposta(:respondeu, codigo: 200, corpo: lido, inicio: inicio)
  rescue SafeFetch::HttpError => e
    resposta(:respondeu, codigo: e.status, corpo: e.body_excerpt, inicio: inicio)
  rescue SafeFetch::UnsafeUrlError, SafeFetch::InvalidUrlError, SafeFetch::CrossOriginRedirectError
    resposta(:recusado_aqui, motivo: 'webhook_endereco_interno', inicio: inicio)
  rescue SafeFetch::FileTooLargeError
    resposta(:respondeu, codigo: 200, motivo: 'webhook_resposta_grande', inicio: inicio)
  rescue SafeFetch::Error
    resposta(:sem_resposta, inicio: inicio)
  end

  def cabecalhos
    instante = Time.now.to_i.to_s
    { 'Content-Type' => 'application/json', 'Accept' => 'application/json', 'User-Agent' => 'Automacao-Webhook',
      'X-Automacao-Execucao' => @execucao_id.to_s, 'X-Automacao-Passo' => @passo_id.to_s, 'X-Automacao-Timestamp' => instante,
      'X-Automacao-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @segredo, "#{instante}.#{@corpo}")}" }
  end

  # `codigo` 200 quer dizer "deu certo (2xx)": o SafeFetch não diz qual 2xx foi.
  def resposta(tipo, codigo: nil, corpo: nil, inicio: nil, motivo: nil)
    ms = inicio && ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    Resposta.new(tipo: tipo, codigo: codigo, host: @host, ms: ms, corpo: corpo, motivo: motivo)
  end
end
