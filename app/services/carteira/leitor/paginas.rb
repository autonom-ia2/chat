# As páginas de um PDF que vão ao modelo (E6, #2899). Tira o texto de cada página sem IA e escolhe poucas: uma apólice
# de 160 páginas não manda 160 páginas ao modelo.
#
# A escolha é por valor exato, nunca por lista de palavras:
# 1. quando já se sabe quem é o segurado, as páginas em que os dígitos do CPF/CNPJ dele aparecem;
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
# O texto das páginas é dado de cliente: não vai para log. O log leva só o número da página e a classe do erro.
class Carteira::Leitor::Paginas
  Pagina = Struct.new(:numero, :texto, keyword_init: true)
  PROCESSADORES = Autonomia::Agents::Knowledge::Processors

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

  # O arquivo não é um PDF, ou o leitor de PDF não o entende (quebrado, com senha).
  class Ilegivel < StandardError; end

  # Quantas páginas o arquivo tem. Só depois de `escolhidas`.
  attr_reader :total

  def initialize(caminho, documento: nil, nome: nil, ocr: false)
    @caminho = caminho.to_s
    @documento = Carteira::Leitor::Ancora.digitos(documento)
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
    raise Ilegivel, 'nao_e_pdf' unless PROCESSADORES::Rasterizacao.pdf?(@caminho)

    require 'pdf-reader'
    @paginas = PDF::Reader.new(@caminho).pages
    @total = @paginas.size
    indices.filter_map do |indice|
      texto = texto_ou_ocr(indice)
      Pagina.new(numero: indice + 1, texto: texto.first(MAXIMO_POR_PAGINA)) unless sem_texto?(texto)
    end
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise Ilegivel, e.class.name
  end

  def indices
    do_documento.presence || do_nome.presence || (0...@total).first(PRIMEIRAS)
  end

  def do_documento
    return [] unless Carteira::Leitor::Ancora::TAMANHOS_DE_DOCUMENTO.include?(@documento.length)

    onde { |texto| Carteira::Leitor::Ancora.digitos(texto).include?(@documento) }
  end

  def do_nome
    return [] if @nome.length < MINIMO_DO_NOME

    onde { |texto| Carteira::Chave.seguradora(texto).include?(@nome) }
  end

  # Os índices das primeiras MAXIMO páginas, até TETO_DE_BUSCA, cujo texto passa na conferência.
  def onde
    (0...@total).first(TETO_DE_BUSCA).lazy.select { |indice| yield texto(indice) }.first(MAXIMO)
  end

  # O texto que o PDF traz na página. Página que o leitor de PDF não entende conta como sem texto.
  def texto(indice)
    @textos[indice] ||= @paginas[indice].text.to_s.force_encoding('UTF-8').scrub('')
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.warn("[carteira][leitor] pagina_ilegivel pagina=#{indice + 1} #{e.class}")
    @textos[indice] = ''
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

    lido = PROCESSADORES::Rasterizacao.pagina(@caminho, indice) { |png| PROCESSADORES::Ocr.ler(png) }
    lido.to_s.force_encoding('UTF-8').scrub('')
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
