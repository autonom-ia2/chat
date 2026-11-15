# Anexar o PDF de um seguro que já existe e ver o que mudou (E6.2, #2899): guarda o arquivo numa leitura de um item só
# (Carteira::Leitura com a marca `anexar`), já ligada ao seguro, e põe a leitura na fila (Carteira::LeituraJob, que
# recebe só o id do item). O seguro não muda aqui: quem muda é o "guardar" depois, com o que a pessoa escolheu
# (Carteira::Pdf::Aceitar).
#
# Conta sem a leitura liberada (Carteira::Leitor::Liberado) recebe `leitura_desligada` sem guardar nada (decisão D4): a
# tela nem chega a pedir, porque o resumo da carteira diz que a leitura está desligada. O arquivo passa pela mesma
# conferência do PDF de um seguro (Carteira::Pdf.conferir!). O arquivo guardado tem nome neutro, como o do seguro.
#
# A leitura que ninguém terminou (a pessoa fechou a tela) fica até a limpeza diária (Carteira::LimpezaDasLeiturasJob).
class Carteira::Pdf::Ler
  DESLIGADA = Carteira::Leitor::Resultado::DESLIGADA

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  # Devolve a leitura criada.
  def call(arquivo)
    recusar(DESLIGADA) unless Carteira::Leitor::Liberado.para?(@apolice.account)
    Carteira::Pdf.conferir!(arquivo)
    item = Carteira::Leitura.transaction { criar(arquivo) }
    Carteira::LeituraJob.perform_later(item.id)
    item.leitura
  end

  private

  def criar(arquivo)
    leitura = Carteira::Leitura.create!(account: @apolice.account, user: @user, origem: 'pdf', estado: 'lendo',
                                        totais: { Carteira::Leitura::DO_ANEXAR => 1 })
    item = leitura.itens.create!(posicao: 0, estado: 'lendo', apolice: @apolice, contact_id: @apolice.contact_id)
    item.pdf.attach(io: arquivo.tempfile, filename: "apolice-#{@apolice.id}.pdf", content_type: Carteira::Pdf::TIPO, identify: false)
    item
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
