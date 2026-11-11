# O CLIENTE HTTP DAS FERRAMENTAS PRONTAS (#2858, F0), sobre o `SafeFetch` (o mesmo das ferramentas do agente).
#
# Proteções, todas aqui e não em cada adaptador:
#   - só host do catálogo: o endereço é montado com o host do provedor e conferido de novo depois de montado; host fora
#     da lista nem sai (`host_fora_do_catalogo`). O `SafeFetch` ainda barra IP privado (SSRF) em cada salto;
#   - só HTTPS na porta 443, também nos redirecionamentos;
#   - redirecionamento só para a mesma origem (`cross_origin_redirects: false`): um salto para outro host é recusado
#     ANTES de ir até lá, então nenhum pedido sai para fora do catálogo;
#   - teto de tamanho da resposta (`MAX_BYTES`), conferido no anúncio e na leitura;
#   - prazo TOTAL monotônico por chamada (`total_timeout`) e o prazo final da consulta: a chamada recebe o menor entre o
#     prazo dela e o que sobra da consulta inteira, somada a reserva. Ressalva do `SafeFetch::Deadline`: o prazo total
#     é relógio único só no CORPO; a conexão (com o TLS) tem o `open_timeout` (até `ABERTURA`) e a espera pelos
#     cabeçalhos tem o `read_timeout`, cada um como teto POR OPERAÇÃO; o DNS fica fora. Então uma chamada pode levar
#     até o prazo dela mais a abertura (pior caso, sem DNS). Cabeçalhos que gotejam abaixo do teto por leitura também
#     escapam (só uma fonte do catálogo comprometida faria isso). Sem repetição do `Net::HTTP` (`max_retries: 0`): ele repetia uma vez o GET
#     que estourou esperando os cabeçalhos, com conexão nova e o prazo inteiro de novo, e a chamada levava o dobro do
#     prazo (#2906: PNCP a frio, prazo de 5 s, 9,8 s medidos). Quem tenta de novo é a consulta (reserva, último dia);
#   - só JSON (ou CSV, onde a fonte oficial só publica CSV: `get_csv`);
#   - teto global por host (`TetoDoProvedor`), contado só no pedido que sai, e o host desligado pela configuração
#     (`TetoDoProvedor.desligado?`): nenhum dos dois chega à rede.
#
# Erro vira `Provedor::Falha` com um motivo curto do código (`tempo_esgotado`, `erro_da_fonte`…): a mensagem de fora
# (que pode trazer o endereço, com o CEP ou o CNPJ) nunca vai a log nem ao modelo.
class Autonomia::FerramentasProntas::ClienteHttp
  Falha = Autonomia::FerramentasProntas::Provedor::Falha
  NaoEncontrado = Autonomia::FerramentasProntas::Provedor::NaoEncontrado

  MAX_BYTES = 256.kilobytes
  PORTA = 443
  MAX_REDIRECTS = 2
  ABERTURA = 2
  # Menos que isto de prazo não dá para uma chamada: a consulta para por prazo, sem chamar.
  MINIMO = 0.3
  # Sem compressão pedida: o teto de tamanho vale sobre o que chega. Fonte que comprime mesmo assim (o IBGE manda gzip
  # com `identity`): o corpo é aberto aqui com o mesmo teto sobre o tamanho aberto (`abrir`), contra bomba de gzip.
  CABECALHOS = { 'Accept' => 'application/json', 'Accept-Encoding' => 'identity',
                 'User-Agent' => 'Autonomia-FerramentasProntas/1.0' }.freeze
  # O que o `SafeFetch` deixa passar do transporte (linha de status ou de bloco inválida, conexão quebrada no meio):
  # falha da fonte, e a reserva tenta.
  TRANSPORTE = [Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error, SystemCallError,
                IOError, OpenSSL::SSL::SSLError, Resolv::ResolvError].freeze
  TIPOS = %w[application/json].freeze
  # O CSV do Banco Central sai como `application/octet-stream`.
  TIPOS_CSV = %w[text/csv application/octet-stream text/plain].freeze
  BOM = "\uFEFF".freeze
  GZIP = "\x1F\x8B".b.freeze
  TEMPO = [Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT].freeze
  # O motivo de cada erro do `SafeFetch` (o primeiro que casa; a ordem importa: o prazo total é um `FetchError`).
  MOTIVOS = [
    [SafeFetch::TotalTimeoutError, 'tempo_esgotado'],
    [SafeFetch::CrossOriginRedirectError, 'redirecionou_para_fora'],
    [SafeFetch::FileTooLargeError, 'resposta_grande_demais'],
    [SafeFetch::UnsafeUrlError, 'endereco_recusado'],
    [SafeFetch::InvalidUrlError, 'endereco_recusado'],
    [SafeFetch::UnsupportedContentTypeError, 'resposta_invalida'],
    [JSON::ParserError, 'resposta_invalida'],
    [EncodingError, 'resposta_invalida']
  ].freeze

  attr_reader :chamadas

  # `hosts`: os do catálogo para esta fonte. `prazo_final`: o instante (relógio monotônico) em que a consulta acaba.
  # `conta`: para a fatia de cada conta no teto global (`TetoDoProvedor`).
  def initialize(hosts:, prazo_final:, conta: nil)
    @conta = conta
    @hosts = hosts.map(&:downcase)
    @de_fora = []
    @prazo_final = prazo_final
    @chamadas = 0
  end

  # O host que só se conhece na hora (o endereço de cada seguradora, lido do diretório do Open Insurance, que já confere
  # HTTPS na 443): passa a valer neste cliente, com as mesmas proteções, a fatia da conta no teto e a contagem. Como veio
  # de fora, ainda é resolvido uma vez aqui e conferido contra rede interna antes de cada pedido (`resolucao`).
  def permitir_host!(host)
    nome = host.to_s.downcase
    @hosts |= [nome]
    @de_fora |= [nome]
  end

  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # -> o JSON lido. `caminho` começa com "/" e é montado só com valores normalizados (`Parametro`). `max_bytes`: o teto
  # da resposta, quando a fonte oficial só entrega a lista inteira (os municípios de MG no IBGE passam de 256 KB).
  # `cabecalhos`: os próprios do provedor (`Provedor.cabecalhos`), por baixo dos fixos daqui.
  def get_json(host, caminho, prazo:, max_bytes: MAX_BYTES, cabecalhos: {})
    ler_json(buscar(host, caminho, prazo: prazo, max_bytes: max_bytes, aceita: { tipos: TIPOS, cabecalhos: cabecalhos }))
  end

  # O mesmo, para o provedor que responde sem corpo quando não há registro (o PNCP manda 204): o vazio vira "não
  # encontrado". Só quem pede: para as outras fontes, 200 vazio continua sendo resposta quebrada. O tipo da resposta não
  # é conferido aqui, porque o 204 pode vir sem `Content-Type`; o corpo que não é JSON continua recusado (`ler_json`).
  def get_json_vazio_e_nao_encontrado(host, caminho, prazo:, max_bytes: MAX_BYTES, cabecalhos: {})
    aceita = { tipos: TIPOS, cabecalhos: cabecalhos, conferir_tipo: false }
    corpo = buscar(host, caminho, prazo: prazo, max_bytes: max_bytes, aceita: aceita)
    raise NaoEncontrado, 'nao_encontrado' if corpo.to_s.strip.empty?

    ler_json(corpo)
  end

  # -> as linhas do CSV (com cabeçalho), em UTF-8.
  def get_csv(host, caminho, prazo:, max_bytes: MAX_BYTES, cabecalhos: {})
    texto = buscar(host, caminho, prazo: prazo, max_bytes: max_bytes, aceita: { tipos: TIPOS_CSV, cabecalhos: cabecalhos })
            .force_encoding(Encoding::UTF_8)
    raise Falha, 'resposta_invalida' unless texto.valid_encoding?

    CSV.parse(texto.delete_prefix(BOM), headers: true)
  rescue CSV::MalformedCSVError
    raise Falha, 'resposta_invalida'
  end

  private

  def ler_json(corpo)
    JSON.parse(corpo)
  rescue JSON::ParserError, EncodingError => e
    raise traduzir(e)
  end

  # `aceita`: os tipos de resposta aceitos (`tipos`) e os cabeçalhos do provedor (`cabecalhos`).
  def buscar(host, caminho, prazo:, max_bytes:, aceita:)
    url = endereco(host, caminho)
    segundos = prazo_da_chamada(prazo)
    fixos = resolucao(host)
    liberar!(host)
    @chamadas += 1
    SafeFetch.fetch(url, **opcoes(segundos, max_bytes, aceita), **fixos) { |resultado| return abrir(resultado.tempfile.read, max_bytes) }
  rescue SafeFetch::Error => e
    raise traduzir(e)
  rescue *TRANSPORTE
    raise Falha, 'falha_de_rede'
  end

  # O corpo em gzip (pelos dois primeiros bytes, não pelo cabeçalho, que a fonte pode omitir) é aberto até `max_bytes`.
  def abrir(corpo, max_bytes)
    return corpo unless corpo.b.start_with?(GZIP)

    aberto = Zlib::GzipReader.wrap(StringIO.new(corpo)) { |gzip| gzip.read(max_bytes + 1) }.to_s
    raise Falha, 'resposta_grande_demais' if aberto.bytesize > max_bytes

    aberto
  rescue Zlib::Error
    raise Falha, 'resposta_invalida'
  end

  # O host que veio de fora (`permitir_host!`): o nome é resolvido UMA vez aqui, todo IP é conferido (privado, loopback,
  # link-local com o metadata, reservado) e o SafeFetch conecta só nesses IPs. Vale também numa instalação com
  # SAFE_FETCH_ALLOW_PRIVATE_NETWORK, em que o SsrfFilter sai do caminho; é a mesma barreira do webhook da Automação.
  # Os hosts fixos do catálogo seguem com a resolução do próprio SafeFetch.
  def resolucao(host)
    return {} unless @de_fora.include?(host.to_s.downcase)

    ips = Resolv.getaddresses(host.to_s).map { |ip| IPAddr.new(ip) }
    raise Falha, 'falha_de_rede' if ips.empty?
    raise Falha, 'endereco_recusado' if ips.any? { |ip| Autonomia::Automacao::EnvioDoWebhook.endereco_interno?(ip) }

    { resolver: ->(_nome) { ips } }
  rescue IPAddr::InvalidAddressError
    raise Falha, 'endereco_recusado'
  end

  def liberar!(host)
    raise Falha, 'provedor_desligado' if Autonomia::FerramentasProntas::TetoDoProvedor.desligado?(host)
    raise Falha, 'teto_do_provedor' unless Autonomia::FerramentasProntas::TetoDoProvedor.reservar!(host, conta: @conta)
  end

  def endereco(host, caminho)
    raise Falha, 'host_fora_do_catalogo' unless @hosts.include?(host.to_s.downcase)
    raise Falha, 'endereco_recusado' unless caminho.to_s.start_with?('/')

    url = "https://#{host}#{caminho}"
    destino = URI.parse(url)
    raise Falha, 'host_fora_do_catalogo' unless destino.host.to_s.casecmp?(host) && destino.userinfo.nil? && destino.port == PORTA

    url
  rescue URI::InvalidURIError
    raise Falha, 'endereco_recusado'
  end

  def prazo_da_chamada(prazo)
    restante = @prazo_final - self.class.agora
    raise Falha, 'prazo_total' if restante < MINIMO

    [prazo, restante].min
  end

  def opcoes(segundos, max_bytes, aceita)
    tipos = aceita.fetch(:tipos)
    {
      method: :get, headers: aceita.fetch(:cabecalhos).merge(CABECALHOS, 'Accept' => tipos.first), max_bytes: max_bytes,
      open_timeout: [ABERTURA, segundos].min, read_timeout: segundos, total_timeout: segundos, max_retries: 0,
      max_redirects: MAX_REDIRECTS, cross_origin_redirects: false, allowed_ports: [PORTA], schemes: %w[https],
      allowed_content_types: tipos, allowed_content_type_prefixes: [], validate_content_type: aceita.fetch(:conferir_tipo, true),
      sensitive_headers: aceita.fetch(:cabecalhos).keys # se um dia o salto para outra origem for aceito, a chave cai antes
    }
  end

  def traduzir(erro)
    return falha_http(erro.status.to_i) if erro.is_a?(SafeFetch::HttpError)

    conhecido = MOTIVOS.find { |classe, _motivo| erro.is_a?(classe) }&.last
    Falha.new(conhecido || (TEMPO.any? { |classe| erro.cause.is_a?(classe) } ? 'tempo_esgotado' : 'falha_de_rede'))
  end

  def falha_http(status)
    return NaoEncontrado.new('nao_encontrado') if status == 404
    return Falha.new('limite_da_fonte') if status == 429
    return Falha.new('erro_da_fonte') if status >= 500

    Falha.new(status.between?(300, 399) ? 'redirecionamento' : 'pedido_recusado')
  end
end
