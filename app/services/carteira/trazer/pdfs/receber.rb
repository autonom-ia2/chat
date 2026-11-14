# Receber os PDFs de "Trazer por PDFs" (E6.3, #2899): cria a leitura do lote e um item por arquivo, e põe cada item na
# fila do leitor (Carteira::LeituraJob, só com o id). A leitura leva a marca `pdfs` em `totais` (com quantos arquivos
# vieram), que a separa da leitura do anexar (Carteira::Leitura.do_trazer).
#
# - De 1 a MAXIMO arquivos por lote; fora disso, `pedido_invalido`. Entrada que não é arquivo: `arquivo_obrigatorio`.
# - O arquivo que não passa na conferência de sempre (Carteira::Pdf.conferir!: tipo, tamanho) não derruba o lote: vira
#   um item `falhou`, sem arquivo, e o motivo é só contado (`motivo_<código>`). A tela diz o que fazer com ele.
# - O arquivo é guardado com nome genérico (`pdf-<posição>.pdf`): o nome que veio do computador da pessoa costuma
#   trazer o nome do cliente.
# Quem chama já conferiu que a leitura está liberada para a conta (decisão D4).
class Carteira::Trazer::Pdfs::Receber
  MAXIMO = 50

  def initialize(account, user:)
    @account = account
    @user = user
  end

  def call(arquivos)
    arquivos = Array(arquivos)
    recusar('pedido_invalido') unless arquivos.size.between?(1, MAXIMO)
    # Entrada que nem arquivo é (o campo veio vazio) é pedido errado, não PDF ruim: recusa o lote todo, com o código.
    recusar('arquivo_obrigatorio') unless arquivos.all?(ActionDispatch::Http::UploadedFile)

    leitura, lendo = Carteira::Leitura.transaction { criar(arquivos) }
    lendo.each { |item| Carteira::LeituraJob.perform_later(item.id) }
    leitura
  end

  private

  def criar(arquivos)
    leitura = Carteira::Leitura.create!(account: @account, user: @user, origem: 'pdf', estado: 'lendo',
                                        totais: { Carteira::Leitura::DO_TRAZER => arquivos.size })
    itens = arquivos.each_with_index.map { |arquivo, posicao| item(leitura, arquivo, posicao) }
    lendo = itens.select { |item| item.estado == 'lendo' }
    leitura.update!(estado: 'lida') if lendo.empty?
    [leitura, lendo]
  end

  def item(leitura, arquivo, posicao)
    Carteira::Pdf.conferir!(arquivo)
    item = leitura.itens.create!(posicao: posicao, estado: 'lendo')
    item.pdf.attach(io: arquivo.tempfile, filename: "pdf-#{posicao + 1}.pdf", content_type: Carteira::Pdf::TIPO, identify: false)
    item
  rescue CustomExceptions::CarteiraRecusa => e
    contar_falha(leitura, e.codigo)
    leitura.itens.create!(posicao: posicao, estado: 'falhou')
  end

  def contar_falha(leitura, codigo)
    totais = leitura.totais.to_h
    leitura.update!(totais: totais.merge('falharam' => totais['falharam'].to_i + 1,
                                         "motivo_#{codigo}" => totais["motivo_#{codigo}"].to_i + 1))
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
