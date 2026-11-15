# Ler o PDF de um seguro que a pessoa tem em outra corretora (E6.5, #2899): guarda o arquivo numa leitura de um item só
# (Carteira::Leitura com a marca `de_fora`), já com o contato da tela e sem apólice, e põe a leitura na fila
# (Carteira::LeituraJob, que recebe só o id do item). O leitor escolhe as páginas pelo CPF/CNPJ do contato, como no
# anexar. Nada é gravado na carteira aqui: quem grava é o Carteira::DeFora::Guardar, com o que a pessoa conferiu.
#
# O arquivo chega de um de dois jeitos:
# - enviado pela tela (`arquivo`): passa pela conferência do PDF de um seguro (Carteira::Pdf.conferir!);
# - escolhido entre os PDFs das conversas da pessoa (`anexo_id`, Carteira::DeFora::Arquivos): o conteúdo é COPIADO para
#   um arquivo novo do item, depois da mesma conferência de tamanho e de tipo pelo conteúdo. O arquivo da conversa nunca
#   é ligado ao item: apagar a leitura apagaria o arquivo da mensagem junto.
# O arquivo do item tem nome neutro: o nome que vem do computador ou da conversa costuma trazer o nome do cliente.
#
# Conta sem a leitura liberada recebe `leitura_desligada` sem guardar nada (decisão D4). A leitura que ninguém terminou
# fica até a limpeza diária (Carteira::LimpezaDasLeiturasJob).
class Carteira::DeFora::Ler
  DESLIGADA = Carteira::Leitor::Resultado::DESLIGADA

  def initialize(pessoa, user:)
    @pessoa = pessoa
    @user = user
  end

  # Devolve a leitura criada.
  def call(arquivo: nil, anexo_id: nil)
    recusar(DESLIGADA) unless Carteira::Leitor::Liberado.para?(@pessoa.account)

    item = anexo_id.present? ? do_anexo(anexo_id) : guardar(Carteira::Pdf.conferir!(arquivo).tempfile)
    Carteira::LeituraJob.perform_later(item.id)
    item.leitura
  end

  private

  def do_anexo(anexo_id)
    anexo = Carteira::DeFora::Arquivos.new(@pessoa, user: @user).anexo(anexo_id)
    recusar('arquivo_obrigatorio') unless anexo
    recusar('arquivo_grande') if anexo.file.blob.byte_size > Carteira::Pdf.limite

    # A gravação fecha dentro do bloco: o arquivo temporário só existe aqui, e o envio ao armazenamento sai no fim dela.
    item = nil
    anexo.file.blob.open do |conteudo|
      recusar('tipo') unless Marcel::MimeType.for(conteudo).to_s == Carteira::Pdf::TIPO
      conteudo.rewind
      item = guardar(conteudo)
    end
    item
  end

  def guardar(conteudo)
    Carteira::Leitura.transaction { criar(conteudo) }
  end

  def criar(conteudo)
    leitura = Carteira::Leitura.create!(account: @pessoa.account, user: @user, origem: 'pdf', estado: 'lendo',
                                        totais: { Carteira::Leitura::DO_DE_FORA => 1 })
    item = leitura.itens.create!(posicao: 0, estado: 'lendo', contact: @pessoa)
    item.pdf.attach(io: conteudo, filename: "seguro-de-fora-#{leitura.id}.pdf", content_type: Carteira::Pdf::TIPO, identify: false)
    item
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
