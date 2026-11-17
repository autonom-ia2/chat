# Os dados do segurado lidos do PDF que já está no seguro, na hora de cotar a renovação (E8.1, #3043). Os seguros que
# chegam do conector já vêm com o PDF da apólice, que ninguém leu. Quando a Entrada (Carteira::Cotacao::Entrada) diz
# que falta algum dado que a apólice traz (nascimento, sexo, CEP, placa ou classe de bônus), o PDF é lido UMA vez e o
# que ele diz preenche o que está vazio. Quem chama monta a Entrada de novo depois.
#
# Só lê quando tudo isto vale, nesta ordem:
# - falta algum dos cinco na Entrada, e a coluna dele está vazia no seguro (na empresa segurada, nascimento e sexo não
#   contam: o portal pede os do condutor, fora deste escopo);
# - o seguro tem PDF;
# - a leitura de PDF está liberada na conta (Carteira::Leitor::Liberado). Chave desligada: nada lido, nada cobrado;
# - o PDF ainda não foi lido para esta vigência. A marca é o passo `dados_lidos_pdf` da vigência, gravado com o seguro
#   travado ANTES da leitura: duas passadas ao mesmo tempo não pagam duas leituras, e a leitura que falha não é
#   tentada de novo (segue com o que tem: a cotação para em "faltou dado" e a equipe é avisada, como sempre).
#
# O que grava: só as colunas dos cinco que estão vazias, relidas com o seguro travado (o que alguém escreveu no meio
# fica). Nunca sobrescreve e nunca toca nas outras colunas do seguro. Só o que o leitor deu como certo (`campos`): o que
# ele deixa "a confirmar" não entra por aqui. A história ganha só o passo da leitura, com a vigência: nenhum valor lido.
#
# Nada do PDF vai para log nem para argumento de job: quem chama roda no job da cotação, com o id do seguro.
class Carteira::Cotacao::DadosDoPdf
  PASSO = 'dados_lidos_pdf'.freeze
  # O nome do que falta na Entrada (no formato do adapter) => a coluna do seguro que o PDF pode preencher.
  DA_ENTRADA = {
    'insured.birthDate' => :segurado_nascimento, 'insured.gender' => :segurado_sexo, 'address.zipCode' => :cep,
    'segurado.cep' => :cep, 'vehicle.plate' => :placa, 'quotation.bonusClass' => :bonus_classe, 'renovacao.bonus' => :bonus_classe
  }.freeze
  DA_PESSOA = %i[segurado_nascimento segurado_sexo].freeze

  # cliente: troca o cliente do modelo (os specs); a trava da conta vale do mesmo jeito.
  def initialize(apolice, cliente: nil)
    @apolice = apolice
    @account = apolice.account
    @cliente = cliente
  end

  # faltam: o que a Entrada disse que falta. -> true quando o PDF foi lido agora (vale montar a Entrada de novo).
  def call(faltam)
    return false unless vale_ler?(faltam) && marcar!

    resultado = ler
    gravar(resultado.campos) if resultado.lido?
    true
  end

  private

  def vale_ler?(faltam)
    colunas = do_segurado(Array(faltam).filter_map { |caminho| DA_ENTRADA[caminho.to_s] })
    colunas.any? { |coluna| @apolice[coluna].nil? } && @apolice.pdf.attached? && Carteira::Leitor::Liberado.para?(@account)
  end

  # Na empresa segurada, nascimento e sexo ficam de fora.
  def do_segurado(colunas)
    @apolice.company_id ? colunas - DA_PESSOA : colunas
  end

  # A leitura desta vigência, marcada uma vez só, com o seguro travado.
  def marcar!
    @apolice.with_lock(requires_new: true) do
      next false if Carteira::Cotacao.passo(@apolice, PASSO)

      Carteira::Cotacao.registrar(@apolice, PASSO)
      true
    end
  end

  # Como a leitura de um item (Carteira::LerItem): o PDF num arquivo temporário, com OCR (estamos num job), e o CPF da
  # pessoa (ou o CNPJ da empresa segurada) para escolher as páginas.
  def ler
    leitor = Carteira::Leitor.new(account: @account, ocr: true, cliente: @cliente)
    segurado = @apolice.company || @apolice.contact
    documento = Relacionamentos::Documentos.new(@account).ler(segurado)&.valor
    @apolice.pdf.open { |arquivo| leitor.ler(arquivo.path, documento: documento, nome: segurado.name) }
  rescue ActiveStorage::FileNotFoundError
    Carteira::Leitor::Resultado.recusado(Carteira::Leitor::Resultado::NAO_DEU, motivo: :sem_arquivo)
  end

  # Só os vazios, relidos com o seguro travado.
  def gravar(campos)
    @apolice.with_lock(requires_new: true) do
      vazios = do_segurado(Carteira::DadosDoSegurado::COLUNAS.select { |coluna| @apolice[coluna].nil? })
      novos = campos.slice(*vazios.map(&:to_s)).compact
      @apolice.update!(novos) if novos.any?
    end
  end
end
