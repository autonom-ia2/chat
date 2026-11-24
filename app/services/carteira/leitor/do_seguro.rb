# A leitura do PDF que já está guardado num seguro (E8.1 #3043, extraída para o #3175). Como a leitura de um item
# (Carteira::LerItem): o PDF num arquivo temporário, com OCR (quem chama roda em job), e o CPF da pessoa (ou o CNPJ da
# empresa segurada) para escolher as páginas por valor exato; sem documento guardado, o nome.
#
# Devolve o Carteira::Leitor::Resultado e não grava nada. A trava da conta (Carteira::Leitor::Liberado) é a do próprio
# leitor. O arquivo que sumiu do armazenamento vira `nao_deu_para_ler` (motivo `sem_arquivo`).
#
# Quem usa: a cotação da renovação (Carteira::Cotacao::DadosDoPdf) e a leitura do PDF que o conector trouxe
# (Carteira::Conector::LerPdf). Nada do PDF, do documento ou do nome vai para log.
class Carteira::Leitor::DoSeguro
  # cliente: troca o cliente do modelo (os specs); a trava da conta vale do mesmo jeito.
  def initialize(apolice, cliente: nil)
    @apolice = apolice
    @account = apolice.account
    @cliente = cliente
  end

  def call
    leitor = Carteira::Leitor.new(account: @account, ocr: true, cliente: @cliente)
    segurado = @apolice.company || @apolice.contact
    documento = Relacionamentos::Documentos.new(@account).ler(segurado)&.valor
    @apolice.pdf.open { |arquivo| leitor.ler(arquivo.path, documento: documento, nome: segurado.name) }
  rescue ActiveStorage::FileNotFoundError
    Carteira::Leitor::Resultado.recusado(Carteira::Leitor::Resultado::NAO_DEU, motivo: :sem_arquivo)
  end
end
