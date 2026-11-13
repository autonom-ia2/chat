# O PDF da apólice (E4, #2897): guardar, tirar e o link para abrir. Nesta entrega o arquivo só fica guardado; ler o que
# ele diz é da entrega seguinte. Um PDF por seguro: guardar outro troca o anterior.
#
# O tipo sai do CONTEÚDO do arquivo (Marcel), não do nome nem do cabeçalho que o navegador manda. O tamanho segue o
# limite de anexo da instalação (MAXIMUM_FILE_UPLOAD_SIZE), o mesmo dos arquivos das conversas. O link é assinado e vale
# pouco: quem o recebe já passou pela permissão de ver a pessoa, e ele não serve para guardar nem repassar.
#
# O arquivo é guardado com um nome neutro (`apolice-<id>.pdf`): o nome que vem do computador de quem envia costuma trazer
# o nome do cliente, o CPF ou o número da apólice, e o nome do arquivo entra no link e no log do armazenamento.
#
# Tirar o PDF não apaga nada da história: fica "PDF anexado" e, depois, "PDF tirado", com quem fez cada um.
class Carteira::Pdf
  TIPO = 'application/pdf'.freeze
  ANEXADO = 'pdf_anexado'.freeze
  TIRADO = 'pdf_tirado'.freeze
  VALIDADE_DO_LINK = 1.minute
  LIMITE_PADRAO_MB = 40
  # O Guia não guarda nem tira PDF por ninguém, nem recebe o link do arquivo (`Guide::Acoes::SO_NA_TELA`): envio de
  # arquivo só se faz na tela, e o link assinado não entra em conversa com IA.
  SO_NA_TELA_DO_GUIA = %w[POST DELETE GET].to_h { |verbo| ["#{verbo} relacionamentos/seguros/:id/pdf", 'seguro_pdf'] }.freeze

  def initialize(apolice, user: nil)
    @apolice = apolice
    @user = user
  end

  def guardar(arquivo)
    conferir(arquivo)
    arquivo.tempfile.rewind
    @apolice.with_lock(requires_new: true) do
      # Atribuir e salvar com `save!`: o `attach` devolve nulo em silêncio quando a apólice não salva.
      @apolice.pdf = { io: arquivo.tempfile, filename: "apolice-#{@apolice.id}.pdf", content_type: TIPO, identify: false }
      @apolice.save!
      anotar(ANEXADO)
    end
    @apolice
  end

  # O arquivo vai para a limpeza depois de a gravação fechar: enfileirado antes, o job poderia apagar o arquivo de um
  # seguro que, se a gravação falhasse, continuaria apontando para ele.
  def tirar
    arquivo = @apolice.with_lock(requires_new: true) { soltar }
    arquivo.purge_later
    @apolice
  end

  def link
    exigir_pdf
    @apolice.pdf.blob.url(expires_in: VALIDADE_DO_LINK, disposition: 'inline')
  end

  private

  # Com a apólice travada e relida: de dois "tirar" ao mesmo tempo, o segundo já não acha o PDF.
  def soltar
    exigir_pdf
    arquivo = @apolice.pdf.blob
    @apolice.pdf.detach
    anotar(TIRADO)
    arquivo
  end

  def anotar(tipo)
    @apolice.eventos.create!(tipo: tipo, quando: Time.current, user: @user)
  end

  def conferir(arquivo)
    recusar('arquivo_obrigatorio') unless arquivo.is_a?(ActionDispatch::Http::UploadedFile)
    recusar('arquivo_grande') if arquivo.size > limite
    recusar('tipo') unless Marcel::MimeType.for(arquivo.tempfile).to_s == TIPO
  end

  def limite
    megabytes = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', LIMITE_PADRAO_MB).to_i
    (megabytes.positive? ? megabytes : LIMITE_PADRAO_MB).megabytes
  end

  def exigir_pdf
    recusar('sem_pdf') unless @apolice.pdf.attached?
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
