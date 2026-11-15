# O PDF da apólice (E4, #2897): guardar, tirar e o link para abrir. Um PDF por seguro: guardar outro troca o anterior.
# Ler o que o PDF diz e mostrar o que mudou é da E6 (#2899): Carteira::Pdf::Ler lê o arquivo num job, e `guardar_lido`
# guarda o PDF que foi lido, com os campos que a pessoa escolheu trocar (Carteira::Pdf::Aceitar).
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
  # arquivo só se faz na tela, e o link assinado não entra em conversa com IA. A leitura do PDF (E6) também: ela recebe
  # o arquivo e devolve o que está escrito na apólice. E trazer seguros por PDF é envio de arquivos.
  SO_NA_TELA_DO_GUIA = %w[POST DELETE GET].to_h { |verbo| ["#{verbo} relacionamentos/seguros/:id/pdf", 'seguro_pdf'] }.merge(
    'POST relacionamentos/seguros/:id/pdf/leitura' => 'seguro_pdf',
    'GET relacionamentos/seguros/:id/pdf/leitura/:leitura_id' => 'seguro_pdf',
    'POST relacionamentos/trazer/seguros/leituras' => 'seguros_por_pdf',
    'POST relacionamentos/trazer/seguros/leituras/:id/trazer' => 'seguros_por_pdf',
    'POST relacionamentos/trazer/seguros/leituras/:id/desfazer' => 'seguros_por_pdf',
    'PATCH relacionamentos/trazer/seguros/leituras/:leitura_id/itens/:id' => 'seguros_por_pdf',
    'PUT relacionamentos/trazer/seguros/leituras/:leitura_id/itens/:id' => 'seguros_por_pdf'
  ).freeze

  # O arquivo que chega pela tela: é um arquivo enviado, cabe no limite e o conteúdo é PDF. Quem lê PDFs (E6) confere
  # pelo mesmo caminho. Recusa com `arquivo_obrigatorio`, `arquivo_grande` ou `tipo`.
  def self.conferir!(arquivo)
    recusar('arquivo_obrigatorio') unless arquivo.is_a?(ActionDispatch::Http::UploadedFile)
    recusar('arquivo_grande') if arquivo.size > limite
    recusar('tipo') unless Marcel::MimeType.for(arquivo.tempfile).to_s == TIPO
    arquivo.tempfile.rewind
    arquivo
  end

  def self.limite
    megabytes = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', LIMITE_PADRAO_MB).to_i
    (megabytes.positive? ? megabytes : LIMITE_PADRAO_MB).megabytes
  end

  def self.recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
  private_class_method :recusar

  def initialize(apolice, user: nil)
    @apolice = apolice
    @user = user
  end

  def guardar(arquivo)
    self.class.conferir!(arquivo)
    @apolice.with_lock(requires_new: true) do
      # Atribuir e salvar com `save!`: o `attach` devolve nulo em silêncio quando a apólice não salva.
      @apolice.pdf = { io: arquivo.tempfile, filename: "apolice-#{@apolice.id}.pdf", content_type: TIPO, identify: false }
      @apolice.save!
      anotar(ANEXADO)
    end
    @apolice
  end

  # O PDF já lido de uma leitura do anexar (`leitura_id`), com os campos que a pessoa escolheu trocar (`usar`).
  def guardar_lido(leitura_id, usar)
    Carteira::Pdf::Aceitar.new(@apolice, user: @user).call(leitura_id, usar)
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

  def exigir_pdf
    recusar('sem_pdf') unless @apolice.pdf.attached?
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
