# O PDF de dentro do ZIP que o portal entrega no lugar do PDF da apólice (#3175). O portal do Agger manda parte dos
# documentos como ZIP com o nome terminado em `.pdf`; Carteira::Conector::BaixarPdf reconhece o ZIP pelo começo do
# arquivo (`PK`) e pede o PDF daqui.
#
# - O PDF é reconhecido pelo CONTEÚDO (começa com `%PDF-`), nunca pelo nome da entrada: o nome vem do portal e pode
#   trazer o nome do cliente. Nenhum nome de entrada é lido para decidir nem vai para log.
# - Precisa haver exatamente UM PDF dentro: nenhum é `zip_sem_pdf`; mais de um é `zip_com_varios_pdfs` (não dá para
#   saber qual é a apólice, e o sistema não chuta). ZIP com mais de MAXIMO_DE_ENTRADAS arquivos é `zip_cheio_demais`.
# - Contra bomba de ZIP, o teto vale duas vezes: o tamanho que o ZIP declara (recusa antes de abrir) e os bytes que a
#   descompressão de fato entrega, contados pedaço a pedaço (o ZIP pode mentir o tamanho). Passou: `grande_demais`.
# - ZIP que não abre (quebrado, com senha, formato que a biblioteca não lê): `zip_quebrado`.
#
# `call` devolve um Tempfile com o PDF, já no começo; quem chama fecha (`close!`). As recusas sobem como Recusa, com o
# código como mensagem (um código nosso, nunca texto do arquivo).
class Carteira::Conector::PdfDoZip
  ASSINATURA_ZIP = 'PK'.b.freeze
  ASSINATURA_PDF = '%PDF-'.b.freeze
  MAXIMO_DE_ENTRADAS = 50
  PEDACO = 64.kilobytes
  Recusa = Class.new(StandardError)

  def self.zip?(arquivo)
    inicio = arquivo.read(ASSINATURA_ZIP.bytesize)
    arquivo.rewind
    inicio == ASSINATURA_ZIP
  end

  def initialize(arquivo, teto:)
    @arquivo = arquivo
    @teto = teto
  end

  def call
    Zip::File.open(@arquivo.path) { |zip| extrair(o_unico_pdf(zip)) }
  rescue Zip::Error, Zlib::Error
    recusar('zip_quebrado')
  end

  private

  def o_unico_pdf(zip)
    arquivos = zip.entries.select(&:file?)
    recusar('zip_cheio_demais') if arquivos.size > MAXIMO_DE_ENTRADAS

    pdfs = arquivos.select { |entrada| pdf?(entrada) }
    recusar('zip_sem_pdf') if pdfs.empty?
    recusar('zip_com_varios_pdfs') if pdfs.size > 1
    pdfs.first
  end

  # Só os primeiros bytes de cada entrada são descompactados para saber se é PDF.
  def pdf?(entrada)
    entrada.get_input_stream { |io| io.read(ASSINATURA_PDF.bytesize) } == ASSINATURA_PDF
  end

  def extrair(entrada)
    recusar('grande_demais') if entrada.size.to_i > @teto

    saida = Tempfile.new(%w[apolice .pdf], binmode: true)
    entrada.get_input_stream { |io| copiar_com_teto(io, saida) }
    saida.rewind
    saida
  rescue StandardError
    saida&.close!
    raise
  end

  def copiar_com_teto(io, saida)
    total = 0
    while (pedaco = io.read(PEDACO))
      total += pedaco.bytesize
      recusar('grande_demais') if total > @teto
      saida.write(pedaco)
    end
  end

  def recusar(codigo)
    raise Recusa, codigo
  end
end
