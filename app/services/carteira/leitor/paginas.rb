# As páginas de um PDF que vão ao modelo (E6, #2899). Tira o texto de cada página sem IA e escolhe poucas: uma apólice
# de 160 páginas não manda 160 páginas ao modelo.
#
# A escolha é por valor exato, nunca por lista de palavras:
# 1. quando já se sabe quem é o segurado, as páginas em que os dígitos do CPF/CNPJ dele aparecem, e as vizinhas
#    imediatas de cada uma (a vigência e o prêmio costumam estar na página ao lado da que traz o CPF);
# 2. sem documento (ou se ele não aparece em nenhuma), as páginas em que o nome dele aparece, sem contar espaço, caixa,
#    acento e pontuação (Carteira::Chave);
# 3. sem nenhum dos dois, as primeiras páginas.
# Nunca mais que MAXIMO páginas, e de cada uma só os primeiros MAXIMO_POR_PAGINA caracteres.
#
# OCR: só na página ESCOLHIDA que não tem texto, e só quando quem chama pede (`ocr: true`). Rasterizar e ler uma página
# leva segundos, então quem pede roda em job; dentro de uma requisição o OCR fica desligado e a página sem texto
# simplesmente não é lida. Reaproveita a rasterização e o OCR da base de conhecimento (Processors::Rasterizacao e
# Processors::Ocr, com os limites de recurso e de tempo deles) e o mesmo teto de pixels por página.
#
# Arquivo que não abre nunca levanta para quem chama com outro erro que não Ilegivel: caminho que não existe, arquivo
# maior que o teto, PDF com senha, truncado ou quebrado. O leitor de PDF lê entrada hostil e levanta de tudo com
# arquivo ruim (os erros dele, de entrada e saída, e até NoMethodError), por isso SÓ as duas chamadas a ele (abrir o
# arquivo e tirar o texto de uma página) pegam qualquer erro, e registram a classe do erro. O resto da classe não
# pega: erro nosso sobe.
#
# O texto das páginas é dado de cliente: não vai para log. O log leva só o número da página e a classe do erro.
class Carteira::Leitor::Paginas
  include Carteira::Leitor::Reservado

  # `tokens`: os pedaços do texto, para a conferência de valor (Carteira::Leitor::Tokens).
  Pagina = Struct.new(:numero, :texto, keyword_init: true) do
    def tokens
      @tokens ||= Carteira::Leitor::Tokens.new(texto)
    end

    # O texto é dado de cliente: não aparece em log nem em mensagem de erro.
    def inspect
      "#<#{self.class.name} numero=#{numero.inspect} caracteres=#{texto.to_s.length}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      { 'numero' => numero }
    end
  end
  PROCESSADORES = Autonomia::Agents::Knowledge::Processors
  TOKENS = Carteira::Leitor::Tokens

  # O maior arquivo que o leitor abre: o limite de anexo que a carteira pratica para o PDF da apólice quando a
  # instalação não configura outro (Carteira::Pdf). Abrir um PDF maior que isso custa memória demais para um job.
  MAXIMO_DE_BYTES = Carteira::Pdf::LIMITE_PADRAO_MB.megabytes

  # Quantas páginas vão ao modelo, no máximo.
  MAXIMO = 6
  # Sem documento nem nome: as primeiras páginas, onde ficam os dados da apólice.
  PRIMEIRAS = 4
  # Até onde procurar o documento ou o nome. Ler o texto de uma página leva milissegundos.
  TETO_DE_BUSCA = 300
  # Uma página A4 cheia tem de 3 a 5 mil caracteres.
  MAXIMO_POR_PAGINA = 6_000
  # Abaixo disto a página "não tem texto" (escaneada ou só imagem): a mesma régua da base de conhecimento.
  MINIMO_DE_TEXTO = 20
  # Nome com menos letras que isto apareceria em qualquer página: não serve para escolher.
  MINIMO_DO_NOME = 5

  # O arquivo não existe, é grande demais, não é um PDF, ou o leitor de PDF não o entende (quebrado, com senha).
  class Ilegivel < StandardError; end

  # Quantas páginas o arquivo tem. Só depois de `escolhidas`.
  attr_reader :total

  def initialize(caminho, documento: nil, nome: nil, ocr: false)
    @caminho = caminho.to_s
    @documento = TOKENS.digitos(documento)
    @nome = Carteira::Chave.seguradora(nome)
    @ocr = ocr
    @textos = {}
  end

  # As páginas escolhidas que têm texto (do próprio PDF ou do OCR), em ordem. Vazio: não há o que mandar ao modelo.
  def escolhidas
    @escolhidas ||= ler
  end

  private

  def ler
    abrir
    indices.filter_map do |indice|
      texto = texto_ou_ocr(indice)
      Pagina.new(numero: indice + 1, texto: texto.first(MAXIMO_POR_PAGINA)) unless sem_texto?(texto)
    end
  end

  # O tamanho é conferido antes de o leitor de PDF tocar no arquivo. As conferências daqui não têm resgate: erro
  # nosso nelas sobe.
  def abrir
    raise Ilegivel, 'nao_existe' unless File.file?(@caminho)
    raise Ilegivel, 'grande_demais' if File.size(@caminho) > MAXIMO_DE_BYTES
    raise Ilegivel, 'nao_e_pdf' unless PROCESSADORES::Rasterizacao.pdf?(@caminho)

    @paginas = paginas_do_pdf
    @total = @paginas.size
  end

  def paginas_do_pdf
    require 'pdf-reader'
    PDF::Reader.new(@caminho).pages
  rescue StandardError => e
    # O registro leva a classe do erro, para um defeito do leitor de PDF não se esconder atrás de "PDF ilegível". Só a
    # classe: a mensagem pode trazer o caminho do arquivo ou um pedaço dele.
    Rails.logger.warn("[carteira][leitor] pdf_nao_abriu #{e.class}")
    raise Ilegivel, e.class.name
  end

  def indices
    com_o_documento = do_documento
    return com_as_vizinhas(com_o_documento) if com_o_documento.any?

    do_nome.presence || (0...@total).first(PRIMEIRAS)
  end

  # As páginas do documento entram todas (já são no máximo MAXIMO); o que sobra do teto vai para as vizinhas, na ordem.
  def com_as_vizinhas(chaves)
    vizinhas = chaves.flat_map { |indice| [indice - 1, indice + 1] }.uniq.select { |indice| indice.between?(0, @total - 1) } - chaves
    (chaves + vizinhas.first(MAXIMO - chaves.size)).sort
  end

  def do_documento
    return [] unless Carteira::Leitor::Ancora::TAMANHOS_DE_DOCUMENTO.include?(@documento.length)

    onde { |texto| TOKENS.digitos(texto).include?(@documento) }
  end

  def do_nome
    return [] if @nome.length < MINIMO_DO_NOME

    onde { |texto| Carteira::Chave.seguradora(texto).include?(@nome) }
  end

  # Os índices das primeiras MAXIMO páginas, até TETO_DE_BUSCA, cujo texto passa na conferência.
  def onde
    (0...@total).first(TETO_DE_BUSCA).lazy.select { |indice| yield texto(indice) }.first(MAXIMO)
  end

  # O texto que o PDF traz na página.
  def texto(indice)
    @textos[indice] ||= em_utf8(do_leitor_de_pdf(indice))
  end

  # Página que o leitor de PDF não entende (qualquer erro dele) conta como sem texto, e o registro leva a classe do
  # erro e o número da página.
  def do_leitor_de_pdf(indice)
    @paginas[indice].text
  rescue StandardError => e
    Rails.logger.warn("[carteira][leitor] pagina_ilegivel pagina=#{indice + 1} #{e.class}")
    ''
  end

  # Sempre uma cópia: o leitor de PDF devolve um texto congelado na página vazia, e marcar a codificação mexe nele.
  def em_utf8(texto)
    texto.to_s.dup.force_encoding('UTF-8').scrub('')
  end

  def sem_texto?(texto)
    texto.strip.length < MINIMO_DE_TEXTO
  end

  def texto_ou_ocr(indice)
    do_pdf = texto(indice)
    return do_pdf unless @ocr && sem_texto?(do_pdf)

    ocr(indice) || do_pdf
  end

  # Falha de UMA página (o ImageMagick ou o tesseract a recusou, estourou o tempo, ou a máquina não tem o tesseract):
  # ela fica sem texto e as outras seguem.
  def ocr(indice)
    return unless cabe?(@paginas[indice])

    em_utf8(PROCESSADORES::Rasterizacao.pagina(@caminho, indice) { |png| PROCESSADORES::Ocr.ler(png) })
  rescue PROCESSADORES::Rasterizacao::Falhou, PROCESSADORES::Ocr::Falhou, PROCESSADORES::Ocr::Indisponivel => e
    Rails.logger.warn("[carteira][leitor] ocr_falhou pagina=#{indice + 1} #{e.class}")
    nil
  end

  # O mesmo teto de pixels do OCR da base: acima dele o ImageMagick, com os limites da Rasterizacao, não comporta.
  def cabe?(pagina)
    largura, altura = PROCESSADORES::TamanhoDaPagina.em_pontos(pagina)
    return false if largura.nil?

    por_ponto = PROCESSADORES::PdfOcr::DPI_POR_PONTO
    (largura * por_ponto) * (altura * por_ponto) <= PROCESSADORES::PdfOcr::MAX_PIXELS_PAGINA
  end
end
