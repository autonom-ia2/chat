# O PDF de dentro do ZIP que o portal entrega no lugar do PDF da apólice (#3175). O portal do Agger manda parte dos
# documentos como ZIP com o nome terminado em `.pdf`; Carteira::Conector::BaixarPdf reconhece o ZIP pelo começo do
# arquivo (`PK`) e pede o PDF daqui.
#
# - O PDF é reconhecido pelo CONTEÚDO (começa com `%PDF-`), nunca pelo nome da entrada: o nome vem do portal e pode
#   trazer o nome do cliente. Nenhum nome de entrada é lido para decidir nem vai para log.
# - Precisa haver exatamente UM PDF dentro: nenhum é `zip_sem_pdf`; mais de um é `zip_com_varios_pdfs` (não dá para
#   saber qual é a apólice, e o sistema não chuta). ZIP com mais de MAXIMO_DE_ENTRADAS entradas é `zip_cheio_demais`,
#   conferido no fim do arquivo (o registro que fecha o ZIP diz quantas entradas há) ANTES de a biblioteca montar a lista
#   inteira na memória. A biblioteca (rubyzip 2.x) acha esse registro do mesmo jeito (o último do arquivo) e monta
#   exatamente aquele número de entradas. O registro tem de fechar no fim exato do arquivo, senão é `zip_quebrado`. ZIP64
#   (onde a biblioteca lê o total de outro registro) é recusado como `zip_cheio_demais`: um PDF de apólice nunca precisa.
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
  FIM_DO_ZIP = "PK\x05\x06".b.freeze
  MARCAS_ZIP64 = ["PK\x06\x06".b, "PK\x06\x07".b].freeze
  # O registro do fim tem 22 bytes e um comentário de até 64 KB; o total de entradas fica no byte 10 dele e o tamanho do
  # comentário no byte 20.
  REGISTRO_DO_FIM = 22
  CAUDA = REGISTRO_DO_FIM + 65_535
  TOTAL_NO_FIM = 10
  COMENTARIO_NO_FIM = 20
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
    recusar('zip_cheio_demais') if entradas_declaradas > MAXIMO_DE_ENTRADAS
    Zip::File.open(@arquivo.path) { |zip| extrair(o_unico_pdf(zip)) }
  rescue Zip::Error, Zlib::Error
    recusar('zip_quebrado')
  end

  private

  # Quantas entradas o ZIP diz ter, lido do registro do fim (o mesmo que a biblioteca usa).
  def entradas_declaradas
    tamanho = File.size(@arquivo.path)
    cauda = File.binread(@arquivo.path, [tamanho, CAUDA].min, [tamanho - CAUDA, 0].max)
    recusar('zip_cheio_demais') if MARCAS_ZIP64.any? { |marca| cauda.include?(marca) }

    inicio = cauda.rindex(FIM_DO_ZIP)
    recusar('zip_quebrado') unless inicio && fecha_no_fim?(cauda, inicio)

    cauda.byteslice(inicio + TOTAL_NO_FIM, 2).unpack1('v')
  end

  def fecha_no_fim?(cauda, inicio)
    return false if cauda.bytesize < inicio + REGISTRO_DO_FIM

    inicio + REGISTRO_DO_FIM + cauda.byteslice(inicio + COMENTARIO_NO_FIM, 2).unpack1('v') == cauda.bytesize
  end

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
