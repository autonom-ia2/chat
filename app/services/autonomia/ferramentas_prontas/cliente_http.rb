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
#     cobre conexão e corpo; DNS e cabeçalhos que gotejam abaixo do teto por leitura escapam dele (só uma fonte do
#     catálogo comprometida faria isso);
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
  def initialize(hosts:, prazo_final:)
    @hosts = hosts.map(&:downcase)
    @prazo_final = prazo_final
    @chamadas = 0
  end

  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # -> o JSON lido. `caminho` começa com "/" e é montado só com valores normalizados (`Parametro`). `max_bytes`: o teto
  # da resposta, quando a fonte oficial só entrega a lista inteira (os municípios de MG no IBGE passam de 256 KB).
  def get_json(host, caminho, prazo:, max_bytes: MAX_BYTES)
    JSON.parse(buscar(host, caminho, prazo: prazo, max_bytes: max_bytes, tipos: TIPOS))
  rescue JSON::ParserError, EncodingError => e
    raise traduzir(e)
  end

  # -> as linhas do CSV (com cabeçalho), em UTF-8.
  def get_csv(host, caminho, prazo:, max_bytes: MAX_BYTES)
    texto = buscar(host, caminho, prazo: prazo, max_bytes: max_bytes, tipos: TIPOS_CSV).force_encoding(Encoding::UTF_8)
    raise Falha, 'resposta_invalida' unless texto.valid_encoding?

    CSV.parse(texto.delete_prefix(BOM), headers: true)
  rescue CSV::MalformedCSVError
    raise Falha, 'resposta_invalida'
  end

  private

  def buscar(host, caminho, prazo:, max_bytes:, tipos:)
    url = endereco(host, caminho)
    segundos = prazo_da_chamada(prazo)
    liberar!(host)
    @chamadas += 1
    SafeFetch.fetch(url, **opcoes(segundos, max_bytes, tipos)) { |resultado| return abrir(resultado.tempfile.read, max_bytes) }
  rescue SafeFetch::Error => e
    raise traduzir(e)
  rescue *TRANSPORTE
    raise Falha, 'falha_de_rede'
  end

  # O corpo em gzip (pelos dois primeiros bytes, não pelo cabeçalho, que a fonte pode omitir) é aberto até `max_bytes`.
  def abrir(corpo, max_bytes)
    return corpo unless corpo.b.start_with?(GZIP)

    aberto = Zlib::GzipReader.new(StringIO.new(corpo)).read(max_bytes + 1).to_s
    raise Falha, 'resposta_grande_demais' if aberto.bytesize > max_bytes

    aberto
  rescue Zlib::Error
    raise Falha, 'resposta_invalida'
  end

  def liberar!(host)
    raise Falha, 'provedor_desligado' if Autonomia::FerramentasProntas::TetoDoProvedor.desligado?(host)
    raise Falha, 'teto_do_provedor' unless Autonomia::FerramentasProntas::TetoDoProvedor.reservar!(host)
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

  def opcoes(segundos, max_bytes, tipos)
    {
      method: :get, headers: CABECALHOS.merge('Accept' => tipos.first), max_bytes: max_bytes,
      open_timeout: [ABERTURA, segundos].min, read_timeout: segundos, total_timeout: segundos,
      max_redirects: MAX_REDIRECTS, cross_origin_redirects: false, allowed_ports: [PORTA], schemes: %w[https],
      allowed_content_types: tipos, allowed_content_type_prefixes: [], validate_content_type: true
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
